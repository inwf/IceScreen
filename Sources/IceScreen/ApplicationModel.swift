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
        if !UserDefaults.standard.bool(forKey: "IceScreen.interactionDefaults.v2") {
            let previousDefault = Shortcut(keyCode: 49, option: true, control: true, function: false, label: "Space")
            if value.shortcut == previousDefault { value.shortcut = Shortcut() }
            do { UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "IceScreen.preferences.v1") }
            catch { fatalError("Cannot persist migrated IceScreen settings: \(error)") }
            UserDefaults.standard.set(true, forKey: "IceScreen.interactionDefaults.v2")
        }
    }
}

@MainActor
final class ApplicationModel: ObservableObject {
    let settings = SettingsStore()
    let catalog = WindowCatalog()
    let hotkeys = HotkeyMonitor()
    private let magnification = PanelMagnificationRouter()
    let media = MediaController()
    let selector = RegionSelector()
    let preview = QuickLookPreview()
    private let detectionActions = DetectionActions()
    private let focusMonitor = SourceFocusMonitor()
    @Published private(set) var sessions: [CaptureSession] = []
    @Published private(set) var screenPermission = false
    @Published private(set) var accessibilityPermission = false
    @Published private(set) var hotkeysActive = false
    @Published private(set) var loginEnabled = false
    @Published var error: String?
    private var ticker: Timer?
    private var mouseGlobal: Any?
    private var mouseLocal: Any?
    private var observers: [NSObjectProtocol] = []
    private var settingsSubscription: AnyCancellable?
    private var lastExternalPID: pid_t?
    private weak var lastHidden: CaptureSession?
    private var captureGeneration = 0
    private var captureTasks: [UUID: Task<Void, Never>] = [:]
    private var selectionTask: Task<Void, Never>?

    init() {
        lastExternalPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        hotkeys.shortcut = settings.value.shortcut
        hotkeys.regionShortcut = settings.value.effectiveRegionShortcut
        hotkeys.closeAllShortcut = settings.value.closeAllShortcut
        hotkeys.quickRegionCapture = settings.value.quickRegionCapture
        hotkeys.quickCaptureModifiers = settings.value.quickCaptureModifiers
        hotkeys.canQuickCapture = { point in
            guard let screen = NSScreen.screens.first else { return false }
            let location = NSPoint(x: point.x, y: screen.frame.maxY - point.y)
            let number = NSWindow.windowNumber(at: location, belowWindowWithWindowNumber: 0)
            return !NSApp.windows.contains { $0.windowNumber == number }
        }
        hotkeys.triggerModifier = settings.value.triggerModifier
        hotkeys.onCapture = { [weak self] region in self?.captureFocused(region: region) }
        hotkeys.onQuickRegion = { [weak self] point in self?.quickCapture(at: point) }
        magnification.sessions = { [weak self] in self?.sessions ?? [] }
        hotkeys.onTrackpadGesture = { [weak self] event, point in
            self?.magnification.handle(event, at: point) ?? false
        }
        hotkeys.onGestureReset = { [weak self] in self?.magnification.reset() }
        hotkeys.onFunctionTap = { [weak self] in self?.toggleHoveredHidden() }
        hotkeys.onFunctionDoubleTap = { [weak self] in
            guard let self, let session = self.hovered(includeHidden: true, includeAutoHidden: true) else { return }
            if session.hidden { session.toggleHidden() }
            session.toggleAutoHide()
        }
        hotkeys.onCloseAll = { [weak self] in self?.closeAll() }
        hotkeys.onHoverAction = { [weak self] action in self?.hoverAction(action) ?? false }
        hotkeys.onSpaceDown = { [weak self] in
            guard let self else { return false }
            if self.preview.isPresented { self.preview.close(); return true }
            guard let session = self.hovered(includeAutoHidden: true) else { return false }
            if self.settings.value.mediaSpace, session.mediaSnapshot != nil {
                self.preview.pressMedia(session, previewEnabled: self.settings.value.quickLook && !session.stageInactive)
                return true
            }
            guard self.settings.value.quickLook else { return false }
            guard !session.stageInactive else { session.showHint("请先返回来源窗口所在的台前调度分组。"); return true }
            self.preview.press(session)
            return true
        }
        hotkeys.onSpaceUp = { [weak self] in self?.preview.release() }
        hotkeys.onSpaceCancel = { [weak self] in self?.preview.close() }
        hotkeys.onEscape = { [weak self] in
            guard let self, self.preview.isPresented else { return false }
            self.preview.close(); return true
        }
        preview.onError = { [weak self] in self?.error = $0.localizedDescription }
        media.onChange = { [weak self] snapshots in self?.sessions.forEach { $0.updateMedia(snapshots) } }
        media.onError = { [weak self] message in self?.sessions.forEach { $0.showHint(message) } }
        detectionActions.onError = { [weak self] in self?.error = $0 }
        detectionActions.onOpen = { [weak self] id in self?.sessions.first { $0.id == id }?.focusSource() }
        focusMonitor.onChange = { [weak self] windowID in
            guard let self else { return }
            for session in Array(self.sessions) {
                session.sourceFocusChanged(windowID: windowID, behavior: self.settings.value.sourceFocusBehavior)
            }
        }
        settingsSubscription = settings.$value.dropFirst().scan((settings.value, settings.value)) { ($0.1, $1) }.sink { [weak self] previous, value in
            guard let self else { return }
            self.hotkeys.shortcut = value.shortcut
            self.hotkeys.regionShortcut = value.effectiveRegionShortcut
            self.hotkeys.closeAllShortcut = value.closeAllShortcut
            self.hotkeys.quickRegionCapture = value.quickRegionCapture
            self.hotkeys.quickCaptureModifiers = value.quickCaptureModifiers
            if previous.triggerModifier != value.triggerModifier { self.hotkeys.triggerModifier = value.triggerModifier }
            if !value.quickLook { self.preview.close() }
            if previous.mediaSpace != value.mediaSpace { self.preview.close() }
            for session in self.sessions {
                session.applyPreferences(value)
                if previous.autoHide != value.autoHide { session.autoHide = value.autoHide }
                if previous.enhanceContrast != value.enhanceContrast { session.enhanced = value.enhanceContrast }
                if previous.idleDetection != value.idleDetection { session.idleDetection = value.idleDetection }
                if previous.changeDetection != value.changeDetection { session.changeDetection = value.changeDetection }
                if previous.sensitiveDetection != value.sensitiveDetection { session.sensitiveDetection = value.sensitiveDetection }
                if previous.fps(for: session.bundleID) != value.fps(for: session.bundleID) {
                    session.setFPS(value.fps(for: session.bundleID))
                }
            }
            if value.detectionNotifications && self.sessions.contains(where: { $0.idleDetection || $0.changeDetection }) {
                self.detectionActions.prepareNotifications()
            }
            if !value.multiWindow { Array(self.sessions.dropLast()).forEach { $0.close() } }
            if previous.mediaControls != value.mediaControls { self.updateMediaMonitoring() }
            if previous.sourceFocusBehavior != value.sourceFocusBehavior {
                DispatchQueue.main.async { [weak self] in self?.focusMonitor.refresh() }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notice in
            MainActor.assumeIsolated {
                guard let self, let app = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.lastExternalPID = app.processIdentifier }
                else { self.checkPermissions() }
                if !self.sessions.isEmpty {
                    self.scheduleStageRefresh()
                    self.focusMonitor.observe(app.processIdentifier)
                    self.focusMonitor.refresh()
                }
            }
        })
        for (name, suspend) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                (NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    let display = name == NSWorkspace.screensDidSleepNotification || name == NSWorkspace.screensDidWakeNotification
                    if suspend { self?.preview.close() }
                    self?.sessions.forEach { $0.suspend(suspend, display: display) }
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notice in
            MainActor.assumeIsolated {
                guard let self, let app = notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.sessions.filter { $0.source.owningApplication?.processID == app.processIdentifier }.forEach { $0.close() }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleStageRefresh() }
        })
        checkPermissions()
    }

    func checkPermissions() {
        screenPermission = CGPreflightScreenCaptureAccess()
        accessibilityPermission = AXIsProcessTrusted()
        if !accessibilityPermission { hotkeys.stop() }
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

    func receive(_ request: CaptureRequest, toggleExisting: Bool = false) {
        selectionTask?.cancel()
        selector.cancel()
        let pid = preferredPID()
        captureGeneration += 1
        let generation = captureGeneration
        let token = UUID()
        captureTasks[token] = Task {
            defer { captureTasks[token] = nil }
            await catalog.refresh()
            guard !Task.isCancelled else { return }
            guard generation == captureGeneration || settings.value.multiWindow else { return }
            if let issue = catalog.error { error = issue; return }
            do {
                let source = try catalog.resolve(request, preferredPID: pid)
                if request.region { selectRegion(source) }
                else { start(source, viewport: .initial(anchor: request.anchor, factor: request.zoom), toggleExisting: toggleExisting) }
            } catch { self.error = error.localizedDescription }
        }
    }

    func captureFocused(region: Bool) {
        selector.cancel()
        var request = CaptureRequest()
        request.region = region
        receive(request, toggleExisting: true)
    }

    private func preferredPID() -> pid_t? {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           pid != ProcessInfo.processInfo.processIdentifier { return pid }
        return lastExternalPID
    }

    func quickCapture(at point: CGPoint) {
        selectionTask?.cancel()
        selector.cancel()
        captureGeneration += 1
        let generation = captureGeneration
        let token = UUID()
        captureTasks[token] = Task {
            defer { captureTasks[token] = nil }
            await catalog.refresh()
            guard !Task.isCancelled, generation == captureGeneration || settings.value.multiWindow else { return }
            if let issue = catalog.error { error = issue; return }
            guard let source = catalog.window(at: point) else { return }
            let x = (point.x - source.frame.minX) / source.frame.width
            let y = (point.y - source.frame.minY) / source.frame.height
            do {
                let viewport = settings.value.smartRegionCapture
                    ? try await SmartRegionCapture.detect(source: source, at: point)
                    : Viewport(rect: CGRect(x: x - 0.125, y: y - 0.125, width: 0.25, height: 0.25))
                guard !Task.isCancelled, generation == captureGeneration || settings.value.multiWindow else { return }
                start(source, viewport: viewport)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    func selectRegion(_ source: SCWindow) {
        selectionTask?.cancel()
        let generation = captureGeneration
        selectionTask = Task {
            do {
                try await catalog.focus(source)
                try await Task.sleep(for: .milliseconds(180))
                await catalog.refresh()
                guard !Task.isCancelled, generation == captureGeneration else { return }
                guard let updated = catalog.windows.first(where: { $0.windowID == source.windowID }), updated.isOnScreen else {
                    throw RequestError.message("请先将来源窗口显示到当前桌面，再选择捕获区域。")
                }
                selector.select(frame: updated.frame) { [weak self] selection in
                    guard let self, let selection, generation == self.captureGeneration else { return }
                    self.start(updated, viewport: selection)
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    func start(_ source: SCWindow, viewport: Viewport = .full, toggleExisting: Bool = false) {
        if let existing = sessions.first(where: { $0.source.windowID == source.windowID }) {
            if toggleExisting, !existing.hidden { existing.close(); return }
            existing.setViewport(viewport)
            if existing.hidden { existing.toggleHidden() }
            if existing.paused { existing.togglePaused() }
            existing.panel.orderFrontRegardless()
            return
        }
        if !settings.value.multiWindow { closeAll(cancelPending: false) }
        let session = CaptureSession(source: source, viewport: viewport, preferences: settings.value, offset: sessions.count)
        session.onClose = { [weak self] value in
            guard let self else { return }
            if self.preview.sourceID == value.source.windowID { self.preview.close() }
            self.detectionActions.close(value.id)
            self.sessions.removeAll { $0.id == value.id }
            if self.sessions.isEmpty { self.stopSessionMonitoring() }
        }
        session.onFocus = { [weak self] source in
            guard let self else { throw CancellationError() }
            try await self.catalog.focus(source)
        }
        session.onPreview = { [weak self, weak session] in
            guard let self, let session else { return }
            guard !session.stageInactive else { session.showHint("请先返回来源窗口所在的台前调度分组。"); return }
            self.preview.show(session)
        }
        session.onMedia = { [weak self] in self?.media.send($0) }
        session.onDetection = { [weak self, weak session] event in
            guard let self, let session else { return }
            self.detectionActions.send(event, session: session, preferences: self.settings.value)
        }
        session.onDetectionEnabled = { [weak self] in
            guard let self, self.settings.value.detectionNotifications else { return }
            self.detectionActions.prepareNotifications()
        }
        session.onFrameRate = { [weak self] app, fps in self?.setFPS(app: app, fps: fps) }
        session.onResize = { [weak self] width in self?.settings.value.preferredWidth = width }
        session.onChange = { [weak self] in self?.objectWillChange.send() }
        sessions.append(session)
        if settings.value.detectionNotifications && (session.idleDetection || session.changeDetection) {
            detectionActions.prepareNotifications()
        }
        session.start()
        updateMediaMonitoring()
        session.updateMedia(media.snapshots)
        startSessionMonitoring()
    }

    func setFPS(app: String, fps: Int) {
        settings.value.appFrameRates[app] = fps
        sessions.filter { $0.bundleID == app }.forEach { $0.setFPS(fps) }
    }

    func closeAll(cancelPending: Bool = true) {
        if cancelPending {
            captureGeneration += 1
            captureTasks.values.forEach { $0.cancel() }
            selectionTask?.cancel()
            selector.cancel()
        }
        Array(sessions).forEach { $0.close() }
    }

    private func hovered(includeHidden: Bool = false, includeAutoHidden: Bool = false) -> CaptureSession? {
        let point = NSEvent.mouseLocation
        let hit = PanelHitTesting.frontmost(at: point, among: sessions.map(\.panel))
        if let hit, let session = sessions.first(where: { $0.panel === hit }), !session.hidden, !session.autoHidden {
            return session
        }
        if includeAutoHidden, let session = sessions.reversed().first(where: {
            $0.autoHidden && $0.panel.isVisible && $0.panel.isOnActiveSpace && $0.panel.frame.contains(point)
        }) {
            return session
        }
        if includeHidden {
            return sessions.reversed().first { $0.hidden && $0.panel.frame.contains(point) }
        }
        return nil
    }

    private func toggleHoveredHidden() {
        if let session = hovered(includeHidden: true, includeAutoHidden: true) {
            session.toggleHidden()
            if session.hidden { lastHidden = session }
        }
        else if let lastHidden, lastHidden.hidden { lastHidden.toggleHidden() }
    }

    private func hoverAction(_ action: HoverAction) -> Bool {
        guard let session = hovered(includeHidden: action == .close, includeAutoHidden: action == .close) else { return false }
        if action == .seekBackward || action == .seekForward {
            return session.seekMedia(relative: action == .seekBackward ? -5 : 5)
        }
        DispatchQueue.main.async { [weak session] in
            guard let session else { return }
            switch action {
            case .frameRate: session.showFrameRateMenu()
            case .idleDetection: session.toggleIdle()
            case .changeDetection: session.toggleChangeDetection()
            case .sensitiveDetection: session.toggleSensitiveDetection()
            case .zoomIn: session.zoomIn()
            case .zoomOut: session.zoomOut()
            case .resetZoom: session.resetZoom()
            case .seekBackward, .seekForward: break
            case .close: session.close()
            }
        }
        return true
    }

    private func startSessionMonitoring() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                Array(self.sessions).forEach { $0.tick(at: now) }
            }
        }
        timer.tolerance = 0.2
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier { focusMonitor.observe(pid) }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        mouseGlobal = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.pointerMoved() }
        mouseLocal = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.pointerMoved(); return event }
    }

    private func pointerMoved() { sessions.forEach { $0.pointerMoved(to: NSEvent.mouseLocation) } }

    private func stopSessionMonitoring() {
        magnification.reset()
        media.stop()
        ticker?.invalidate(); ticker = nil
        focusMonitor.stop()
        if let mouseGlobal { NSEvent.removeMonitor(mouseGlobal); self.mouseGlobal = nil }
        if let mouseLocal { NSEvent.removeMonitor(mouseLocal); self.mouseLocal = nil }
    }

    private func updateMediaMonitoring() {
        if !sessions.isEmpty && settings.value.mediaControls { media.start() }
        else { media.stop() }
    }

    private var stageRefreshTask: Task<Void, Never>?
    private func scheduleStageRefresh() {
        stageRefreshTask?.cancel()
        stageRefreshTask = Task { [weak self] in
            for delay in [100, 250, 500] {
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                self?.sessions.forEach { $0.refreshSourceState() }
            }
        }
    }

    func shutdown() {
        selector.cancel()
        preview.close()
        closeAll()
        stageRefreshTask?.cancel()
        detectionActions.shutdown()
        stopSessionMonitoring()
        hotkeys.stop()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
}
#endif
