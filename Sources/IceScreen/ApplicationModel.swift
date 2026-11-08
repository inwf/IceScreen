#if os(macOS)
import AppKit
import SwiftUI
import ScreenCaptureKit
import ApplicationServices
import ServiceManagement
import Combine
import IceCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: Preferences {
        didSet {
            do { UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "IceScreen.preferences.v1") }
            catch { fatalError("Cannot encode IceScreen settings: \(error)") }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "IceScreen.preferences.v1") {
            do { value = try JSONDecoder().decode(Preferences.self, from: data); value.normalize() }
            catch { fatalError("Cannot read IceScreen settings: \(error)") }
        } else { value = Preferences() }
    }
}

@MainActor
final class ApplicationModel: ObservableObject {
    let settings = SettingsStore()
    let catalog = WindowCatalog()
    let hotkeys = HotkeyMonitor()
    let selector = RegionSelector()
    @Published private(set) var sessions: [CaptureSession] = []
    @Published private(set) var screenPermission = false
    @Published private(set) var accessibilityPermission = false
    @Published private(set) var hotkeysActive = false
    @Published private(set) var loginEnabled = false
    @Published var error: String?
    @Published var selectedPage = "windows"
    private var ticker: Timer?
    private var mouseGlobal: Any?
    private var mouseLocal: Any?
    private var observers: [NSObjectProtocol] = []
    private var settingsSubscription: AnyCancellable?
    private var lastExternalPID: pid_t?
    private weak var lastHidden: CaptureSession?

    init() {
        lastExternalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        hotkeys.shortcut = settings.value.shortcut
        hotkeys.onCapture = { [weak self] region in self?.captureFocused(region: region) }
        hotkeys.onQuickRegion = { [weak self] point in self?.quickCapture(at: point) }
        hotkeys.onFunctionTap = { [weak self] in self?.toggleHoveredHidden() }
        hotkeys.onHoverKey = { [weak self] key in self?.hoverKey(key) ?? false }
        settingsSubscription = settings.$value.dropFirst().sink { [weak self] value in
            guard let self else { return }
            self.hotkeys.shortcut = value.shortcut
            for session in self.sessions { session.idleSeconds = value.idleSeconds }
            if !value.multiWindow { Array(self.sessions.dropLast()).forEach { $0.close() } }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notice in
            MainActor.assumeIsolated {
                guard let self, let app = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.lastExternalPID = app.processIdentifier }
                else { self.checkPermissions() }
            }
        })
        for (name, suspend) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sessions.forEach { $0.suspend(suspend) } }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notice in
            MainActor.assumeIsolated {
                guard let self, let app = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.sessions.filter { $0.source.owningApplication?.processID == app.processIdentifier }.forEach { $0.close() }
            }
        })
        checkPermissions()
    }

    func checkPermissions() {
        screenPermission = CGPreflightScreenCaptureAccess()
        accessibilityPermission = AXIsProcessTrusted()
        hotkeysActive = accessibilityPermission && hotkeys.start()
        loginEnabled = SMAppService.mainApp.status == .enabled
    }

    func requestScreenPermission() {
        CGRequestScreenCaptureAccess()
        openPrivacy("Privacy_ScreenCapture")
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }

    private func openPrivacy(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = error.localizedDescription }
    }

    func receive(_ request: CaptureRequest) {
        let pid = preferredPID()
        Task {
            await catalog.refresh()
            if let issue = catalog.error { error = issue; return }
            do {
                let source = try catalog.resolve(request, preferredPID: pid)
                if request.region { selectRegion(source) }
                else { start(source, viewport: .initial(anchor: request.anchor, factor: request.zoom)) }
            } catch { self.error = error.localizedDescription }
        }
    }

    func captureFocused(region: Bool) {
        var request = CaptureRequest()
        request.region = region
        receive(request)
    }

    private func preferredPID() -> pid_t? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           pid != ProcessInfo.processInfo.processIdentifier { return pid }
        return lastExternalPID
    }

    func quickCapture(at point: CGPoint) {
        Task {
            await catalog.refresh()
            if let issue = catalog.error { error = issue; return }
            guard let source = catalog.window(at: point) else { return }
            let x = (point.x - source.frame.minX) / source.frame.width
            let y = (point.y - source.frame.minY) / source.frame.height
            start(source, viewport: Viewport(rect: CGRect(x: x - 0.125, y: y - 0.125, width: 0.25, height: 0.25)))
        }
    }

    func selectRegion(_ source: SCWindow) {
        Task {
            do {
                try catalog.focus(source)
                try await Task.sleep(for: .milliseconds(180))
                await catalog.refresh()
                guard let updated = catalog.windows.first(where: { $0.windowID == source.windowID }), updated.isOnScreen else {
                    throw RequestError.message("请先将来源窗口显示到当前桌面，再选择捕获区域。")
                }
                selector.select(frame: updated.frame) { [weak self] selection in
                    if let selection { self?.start(updated, viewport: selection) }
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    func start(_ source: SCWindow, viewport: Viewport = .full) {
        if let existing = sessions.first(where: { $0.source.windowID == source.windowID }) {
            existing.setViewport(viewport)
            if existing.hidden { existing.toggleHidden() }
            if existing.paused { existing.togglePaused() }
            existing.panel.orderFrontRegardless()
            return
        }
        if !settings.value.multiWindow { closeAll() }
        let session = CaptureSession(source: source, viewport: viewport, preferences: settings.value, offset: sessions.count)
        session.onClose = { [weak self] value in
            guard let self else { return }
            self.sessions.removeAll { $0.id == value.id }
            if self.sessions.isEmpty { self.stopSessionMonitoring() }
        }
        session.onFocus = { [weak self] source in
            do { try self?.catalog.focus(source) } catch { self?.error = error.localizedDescription }
        }
        session.onFrameRate = { [weak self] app, fps in self?.setFPS(app: app, fps: fps) }
        session.onResize = { [weak self] width in self?.settings.value.preferredWidth = width }
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        sessions.append(session)
        session.start()
        startSessionMonitoring()
    }

    func setFPS(app: String, fps: Int) {
        settings.value.appFrameRates[app] = fps
        sessions.filter { $0.bundleID == app }.forEach { $0.setFPS(fps) }
    }

    func closeAll() { Array(sessions).forEach { $0.close() } }

    private func hovered() -> CaptureSession? {
        let point = NSEvent.mouseLocation
        return sessions.reversed().first { !$0.hidden && $0.panel.frame.contains(point) }
    }

    private func toggleHoveredHidden() {
        if let session = hovered() { session.toggleHidden(); lastHidden = session }
        else if let lastHidden, lastHidden.hidden { lastHidden.toggleHidden() }
    }

    private func hoverKey(_ key: UInt16) -> Bool {
        let session = hovered() ?? ((key == 51 || key == 117) ? lastHidden : nil)
        guard let session else { return false }
        switch key {
        case 3: session.cycleFPS()
        case 2: session.toggleIdle()
        case 24, 69: session.zoomIn()
        case 27, 78: session.zoomOut()
        case 51, 117: session.close()
        default: return false
        }
        return true
    }

    private func startSessionMonitoring() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                Array(self.sessions).forEach { $0.tick(at: now) }
            }
        }
        ticker?.tolerance = 0.2
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        mouseGlobal = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.pointerMoved() }
        mouseLocal = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.pointerMoved(); return event }
    }

    private func pointerMoved() { sessions.forEach { $0.pointerMoved(to: NSEvent.mouseLocation) } }

    private func stopSessionMonitoring() {
        ticker?.invalidate(); ticker = nil
        if let mouseGlobal { NSEvent.removeMonitor(mouseGlobal); self.mouseGlobal = nil }
        if let mouseLocal { NSEvent.removeMonitor(mouseLocal); self.mouseLocal = nil }
    }

    func shutdown() {
        selector.cancel()
        closeAll()
        stopSessionMonitoring()
        hotkeys.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
#endif
