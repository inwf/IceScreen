#if os(macOS)
import AppKit
import ScreenCaptureKit
import SwiftUI
import OSLog
import IceCore

@MainActor
final class CaptureSession: NSObject, ObservableObject, Identifiable, NSWindowDelegate {
    private static let interactionLog = Logger(subsystem: "org.icescreen.app", category: "PanelInteraction")
    let id = UUID()
    let source: SCWindow
    let pipeline: CapturePipeline
    let panel: FloatingPanel
    let surface: PanelSurface
    @Published private(set) var fps: Int
    @Published private(set) var viewport: Viewport
    @Published private var visibility = PanelVisibility()
    var paused: Bool { visibility.paused }
    var hidden: Bool { visibility.manuallyHidden }
    var autoHidden: Bool { visibility.automaticallyHidden }
    @Published private(set) var idle = false
    @Published var autoHide: Bool { didSet { pointerMoved(to: NSEvent.mouseLocation); updateStatus() } }
    @Published var idleDetection: Bool { didSet { configureDetection() } }
    @Published var changeDetection: Bool { didSet { configureDetection() } }
    @Published var sensitiveDetection: Bool { didSet { configureDetection() } }
    @Published var enhanced: Bool { didSet { surface.frameView.enhanced = enhanced } }
    @Published private(set) var failure: String?
    var idleSeconds: Double
    var changeSeconds: Double
    var onDetection: ((DetectionEvent) -> Void)?
    var onDetectionEnabled: (() -> Void)?
    var onClose: ((CaptureSession) -> Void)?
    var onFocus: ((SCWindow) async throws -> Void)?
    var onPreview: (() -> Void)?
    var onFrameRate: ((String, Int) -> Void)?
    var onResize: ((Double) -> Void)?
    var onChange: (() -> Void)?
    private var resizeTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var closeAfterFocus = false
    private var closed = false
    private var userIsResizing = false
    private var sourceSize: CGSize
    private var lastGeometryCheck: TimeInterval = 0
    private var sourcePaused = false
    private var preserveOnSourceFocus = false
    private var clickToFocus = false
    private var panelOpacity = 1.0
    private var triggerLabel = "fn"
    private var interactionDepth = 0
    private var detection = ContentDetection()
    private var detectionSuspended = true
    private var detectedChangeUntil: TimeInterval = 0
    var currentSourceSize: CGSize { sourceSize }

    var title: String { source.title?.isEmpty == false ? source.title! : appName }
    var appName: String { source.owningApplication?.applicationName ?? "Window" }
    var bundleID: String { source.owningApplication?.bundleIdentifier ?? appName }
    var status: String {
        if let failure { return failure }
        if hidden { return "已隐藏 · 60 秒后关闭" }
        if autoHidden { return "鼠标穿透" }
        if paused { return "已暂停" }
        if idle { return "内容暂时没有变化" }
        return "\(fps) FPS · \(String(format: "%.1f", viewport.magnification))×"
    }

    init(source: SCWindow, viewport: Viewport, preferences: Preferences, offset: Int) {
        self.source = source
        self.sourceSize = source.frame.size
        self.viewport = viewport
        fps = preferences.fps(for: source.owningApplication?.bundleIdentifier ?? "")
        autoHide = preferences.autoHide
        idleDetection = preferences.idleDetection
        changeDetection = preferences.changeDetection
        sensitiveDetection = preferences.sensitiveDetection
        enhanced = preferences.enhanceContrast
        idleSeconds = preferences.idleSeconds
        changeSeconds = preferences.changeSeconds
        pipeline = CapturePipeline(source: source)
        let ratio = (source.frame.width * viewport.rect.width) / (source.frame.height * viewport.rect.height)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let width = min(preferences.preferredWidth, screen.width * 0.8, screen.height * 0.8 * ratio)
        let size = CGSize(width: width, height: width / ratio)
        let anchor = preferences.panelPosition.point
        let rect = CGRect(x: screen.minX + 24 + (screen.width - width - 48) * anchor.x - CGFloat(offset % 5) * 16,
                          y: screen.minY + 24 + (screen.height - size.height - 48) * (1 - anchor.y) + CGFloat(offset % 5) * 16,
                          width: size.width, height: size.height)
        panel = FloatingPanel(contentRect: rect, styleMask: [.borderless, .resizable, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        surface = PanelSurface(frame: CGRect(origin: .zero, size: size))
        super.init()
        panel.title = "IceScreen · \(title)"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.minSize = CGSize(width: 80, height: 40)
        panel.contentAspectRatio = CGSize(width: ratio, height: 1)
        panel.contentView = surface
        panel.delegate = self
        surface.owner = self
        surface.onContentClick = { [weak self] in self?.clicked() }
        applyPreferences(preferences)
        surface.frameView.enhanced = enhanced
        pipeline.output.mailbox.deliver = { [weak surface] buffer in surface?.frameView.display(buffer) }
        pipeline.output.onActivity = { [weak self] initial in
            guard let self, !self.closed, !self.detectionSuspended else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let changed = self.detection.activity(at: now, initial: initial, changeAfter: self.changeSeconds) == .change
            let wasIdle = self.idle
            self.idle = false
            if changed && self.changeDetection {
                self.detectedChangeUntil = now + 3
                self.onDetection?(.change)
            }
            if wasIdle || (changed && self.changeDetection) { self.updateStatus() }
        }
        configureDetection()
        pipeline.onError = { [weak self] error in
            guard let self else { return }
            self.failure = error.localizedDescription
            self.visibility.paused = true
            self.syncRunning()
            self.updateStatus()
        }
        updateStatus()
    }

    func start() {
        panel.orderFrontRegardless()
        configure()
        syncRunning()
        pointerMoved(to: NSEvent.mouseLocation)
    }

    private func configure() {
        surface.layoutSubtreeIfNeeded()
        pipeline.configure(viewport: viewport, sourceSize: sourceSize, size: surface.frameView.bounds.size,
                           scale: panel.backingScaleFactor, fps: fps)
    }

    private func syncRunning() {
        let running = !closed && !sourcePaused && visibility.shouldCapture
        if detectionSuspended == running {
            detectionSuspended = !running
            detection.reset()
            idle = false
        }
        pipeline.setRunning(running)
    }

    private func configureDetection() {
        detection.reset()
        idle = false
        detectedChangeUntil = 0
        pipeline.output.configureIdle(idleDetection || changeDetection, sensitive: sensitiveDetection)
        if idleDetection || changeDetection { onDetectionEnabled?() }
        updateStatus()
    }

    func suspend(_ value: Bool, display: Bool) {
        if display { visibility.displaySleeping = value } else { visibility.systemSleeping = value }
        syncRunning()
    }

    func setViewport(_ value: Viewport) {
        guard viewport != value else { return }
        let oldRatio = viewport.rect.width / viewport.rect.height
        viewport = value
        configureDetection()
        if abs(oldRatio - value.rect.width / value.rect.height) > 0.00001 { fitPanelToContent() }
        configure()
        idle = false
        updateStatus()
    }

    private func fitPanelToContent() {
        let value = viewport
        let ratio = (sourceSize.width * value.rect.width) / (sourceSize.height * value.rect.height)
        let visible = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let frame = PanelGeometry.fittedFrame(panel.frame, aspectRatio: ratio, visibleFrame: visible)
        panel.contentAspectRatio = CGSize(width: ratio, height: 1)
        panel.setFrame(frame, display: true)
    }

    func setFPS(_ value: Int) {
        guard Preferences.frameRates.contains(value) else { return }
        fps = value
        configure()
        updateStatus()
    }

    func applyPreferences(_ value: Preferences) {
        idleSeconds = value.idleSeconds
        changeSeconds = value.changeSeconds
        clickToFocus = value.clickToFocus
        surface.clickToFocus = value.clickToFocus
        surface.previewEnabled = value.quickLook
        surface.applyAppearance(value, enhanced: enhanced)
        panelOpacity = value.panelOpacity
        if !autoHidden { panel.alphaValue = panelOpacity }
        triggerLabel = value.triggerModifier.display
        surface.triggerLabel = triggerLabel
        panel.collectionBehavior = value.showOnFullscreenSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary] : [.canJoinAllSpaces, .stationary]
    }

    func sourceFocusChanged(windowID: CGWindowID?, behavior: SourceFocusBehavior) {
        let focused = windowID == source.windowID
        if !focused && focusTask == nil { preserveOnSourceFocus = false }
        if focused && behavior == .close && !preserveOnSourceFocus { close(); return }
        sourcePaused = focused && behavior == .pause
        syncRunning()
        updateStatus()
    }

    func clicked() {
        Self.interactionLog.debug("Content click: enabled=\(self.clickToFocus), closed=\(self.closed)")
        guard clickToFocus, !closed else { return }
        focusSource()
    }

    func doubleClicked(reset: Bool) {
        if reset { resetZoom() }
        else { requestFocus(closeAfter: true) }
    }

    func showFrameRateMenu() {
        beginInteraction()
        defer { endInteraction() }
        let point = surface.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        frameRateMenu().popUp(positioning: nil, at: point, in: surface)
    }

    func showThresholdMenu() {
        beginInteraction()
        defer { endInteraction() }
        let menu = NSMenu()
        let current = changeDetection ? changeSeconds : idleSeconds
        for seconds in [2, 5, 10, 20, 30, 60, 120] {
            let item = NSMenuItem(title: "\(seconds) 秒", action: #selector(chooseThreshold(_:)), keyEquivalent: "")
            item.target = self; item.tag = seconds
            item.state = current == Double(seconds) ? .on : .off
            menu.addItem(item)
        }
        let point = surface.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        menu.popUp(positioning: nil, at: point, in: surface)
    }

    @objc private func chooseThreshold(_ sender: NSMenuItem) {
        if changeDetection { changeSeconds = Double(sender.tag) }
        else { idleSeconds = Double(sender.tag) }
        configureDetection()
    }

    @objc func togglePaused() {
        visibility.paused.toggle()
        failure = nil
        syncRunning()
        updateStatus()
    }

    @objc func toggleIdle() { idleDetection.toggle() }
    @objc func toggleChangeDetection() { changeDetection.toggle() }
    @objc func toggleSensitiveDetection() { sensitiveDetection.toggle() }
    @objc func toggleHoverDim() { surface.dimOnHover.toggle() }
    @objc func toggleEnhanced() { enhanced.toggle(); updateStatus() }
    @objc func toggleAutoHide() { autoHide.toggle() }
    @objc func focusSource() {
        requestFocus(closeAfter: false)
    }
    private func requestFocus(closeAfter: Bool) {
        guard !closed, let onFocus else { return }
        preserveOnSourceFocus = true
        closeAfterFocus = closeAfterFocus || closeAfter
        guard focusTask == nil else { return }
        failure = nil
        updateStatus()
        focusTask = Task { [weak self] in
            guard let self else { return }
            defer { self.focusTask = nil; self.closeAfterFocus = false }
            do {
                try await onFocus(self.source)
                try Task.checkCancellation()
                Self.interactionLog.debug("Source window focus confirmed")
                if self.closeAfterFocus { self.close() }
            } catch {
                self.preserveOnSourceFocus = false
                if !Task.isCancelled && !(error is CancellationError) {
                    self.failure = error.localizedDescription
                    self.updateStatus()
                    Self.interactionLog.error("Source window focus failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    @objc func showPreview() { onPreview?() }
    @objc func resetZoom() { setViewport(.full) }
    @objc func zoomIn() { setViewport(viewport.zoomed(by: 1.25)) }
    @objc func zoomOut() { setViewport(viewport.zoomed(by: 0.8)) }

    @objc func toggleHidden() {
        visibility.toggleManual(at: ProcessInfo.processInfo.systemUptime)
        if hidden {
            panel.orderOut(nil)
            surface.frameView.releaseFrame()
        } else {
            panel.alphaValue = panelOpacity
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
        }
        syncRunning()
        updateStatus()
    }

    func pointerMoved(to point: CGPoint) {
        guard !hidden, !closed else { return }
        let inside = panel.frame.contains(point)
        surface.setHovered(inside)
        let previous = autoHidden
        visibility.updatePointer(inside: inside, autoHide: autoHide)
        if previous != autoHidden { applyAutoHidden() }
    }

    private func applyAutoHidden() {
        let value = autoHidden
        panel.ignoresMouseEvents = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = value ? 0 : panelOpacity
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.autoHidden, !self.closed else { return }
                self.surface.frameView.redraw()
            }
        }
        syncRunning()
        if value { surface.frameView.releaseFrame() }
        updateStatus()
    }

    func beginInteraction() {
        interactionDepth += 1
        visibility.interacting = true
        pointerMoved(to: NSEvent.mouseLocation)
    }
    func endInteraction() {
        interactionDepth = max(0, interactionDepth - 1)
        visibility.interacting = interactionDepth > 0
        pointerMoved(to: NSEvent.mouseLocation)
    }

    func tick(at now: TimeInterval) {
        if visibility.isExpired(at: now) { close(); return }
        if !visibility.systemSleeping, !visibility.displaySleeping, now - lastGeometryCheck >= 2 {
            lastGeometryCheck = now
            checkSourceGeometry()
        }
        if detectedChangeUntil > 0, now >= detectedChangeUntil { detectedChangeUntil = 0; updateStatus() }
        guard idleDetection, !detectionSuspended else { return }
        if detection.tick(at: now, idleAfter: idleSeconds) == .idle {
            idle = true
            updateStatus()
            onDetection?(.idle)
        }
    }

    private func checkSourceGeometry() {
        guard let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, source.windowID) as? [[String: Any]] else { return }
        guard let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == source.windowID }) else {
            close(); return
        }
        guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), frame.width > 0, frame.height > 0 else { return }
        if sourceSize != frame.size { sourceSize = frame.size; fitPanelToContent(); configure() }
    }

    func updateStatus() {
        surface.update(title: title, status: status, idle: idle, detection: idleDetection || changeDetection,
                       message: failure ?? (paused || sourcePaused ? "捕获已暂停" : (detectedChangeUntil > 0 ? "检测到新的画面变化" : nil)))
        onChange?()
    }

    @objc func close() {
        focusTask?.cancel()
        guard !closed else { return }
        closed = true
        resizeTask?.cancel()
        pipeline.close()
        surface.frameView.releaseFrame()
        panel.orderOut(nil)
        panel.close()
        onClose?(self)
    }

    func windowWillClose(_ notification: Notification) { close() }
    func windowWillStartLiveResize(_ notification: Notification) { userIsResizing = true; beginInteraction() }
    func windowDidEndLiveResize(_ notification: Notification) {
        userIsResizing = false
        onResize?(Double(panel.frame.width))
        configure()
        endInteraction()
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let ratio = (sourceSize.width * viewport.rect.width) / (sourceSize.height * viewport.rect.height)
        if abs(frameSize.height - panel.frame.height) * ratio > abs(frameSize.width - panel.frame.width) {
            return CGSize(width: frameSize.height * ratio, height: frameSize.height)
        }
        return CGSize(width: frameSize.width, height: frameSize.width / ratio)
    }
    func windowDidResize(_ notification: Notification) {
        guard !userIsResizing else { return }
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            self?.configure()
        }
    }
    func windowDidChangeBackingProperties(_ notification: Notification) { configure() }

    func beginHandleResize() {
        resizeTask?.cancel()
        userIsResizing = true
        beginInteraction()
    }

    func endHandleResize() {
        userIsResizing = false
        if !closed { onResize?(Double(panel.frame.width)); configure() }
        endInteraction()
    }

    @objc func chooseFPS(_ sender: NSMenuItem) { onFrameRate?(bundleID, sender.tag) }

    private func frameRateMenu() -> NSMenu {
        let menu = NSMenu()
        for rate in Preferences.frameRates {
            let item = NSMenuItem(title: "\(rate) FPS", action: #selector(chooseFPS(_:)), keyEquivalent: "")
            item.target = self; item.tag = rate; item.state = fps == rate ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func detectionMenu() -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "内容检测", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        for (title, action, enabled) in [
            ("空闲提醒 · D", #selector(toggleIdle), idleDetection),
            ("变化提醒 · C", #selector(toggleChangeDetection), changeDetection),
            ("细微变化 · S", #selector(toggleSensitiveDetection), sensitiveDetection)
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.state = enabled ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let checked { item.state = checked ? .on : .off }
            menu.addItem(item)
        }
        add("定位来源窗口", #selector(focusSource))
        if surface.previewEnabled { add("预览来源窗口", #selector(showPreview)) }
        add(paused ? "继续捕获" : "暂停捕获", #selector(togglePaused))
        add("恢复完整画面", #selector(resetZoom))
        let fpsItem = NSMenuItem(title: "应用帧率", action: nil, keyEquivalent: "")
        fpsItem.submenu = frameRateMenu()
        menu.addItem(fpsItem)
        menu.addItem(.separator())
        add("鼠标移入时自动隐藏", #selector(toggleAutoHide), checked: autoHide)
        add("悬停时控件周围变暗", #selector(toggleHoverDim), checked: surface.dimOnHover)
        add("检测内容空闲", #selector(toggleIdle), checked: idleDetection)
        add("检测画面变化", #selector(toggleChangeDetection), checked: changeDetection)
        add("检测细微变化", #selector(toggleSensitiveDetection), checked: sensitiveDetection)
        add("增强对比度和清晰度", #selector(toggleEnhanced), checked: enhanced)
        menu.addItem(.separator())
        add(hidden ? "恢复显示" : "暂时隐藏", #selector(toggleHidden))
        add("关闭浮窗", #selector(close))
        return menu
    }
}

@MainActor
final class PanelSurface: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    let frameView = FrameView(frame: .zero)
    private let input = PanelInput(frame: .zero)
    private let resizeInput = PanelResizeHandle(frame: .zero)
    private let chromeState = PanelChromeState()
    private var controls: PanelChromeHost!
    private let dim = PanelDimView()
    private var statusMessage: String?
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var detectionEnabled = false
    var onContentClick: (() -> Void)? { didSet { input.onClick = onContentClick } }
    var showHints = true { didSet { updateHint() } }
    var triggerLabel = "fn" { didSet { updateHint() } }
    var clickToFocus = true { didSet { updateHint() } }
    var previewEnabled = true { didSet { updateHint() } }
    var dimOnHover = true { didSet { updateHint() } }
    var hoverBlur: Double = Preferences().hoverBlur { didSet { dim.strength = hoverBlur } }
    weak var owner: CaptureSession? { didSet { input.owner = owner; resizeInput.owner = owner } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 12
        clipsToBounds = false
        layer?.masksToBounds = false
        frameView.layer?.cornerRadius = 12
        frameView.layer?.masksToBounds = true
        dim.wantsLayer = true
        dim.layer?.cornerRadius = 12
        dim.layer?.masksToBounds = true
        addSubview(frameView)
        addSubview(input)
        addSubview(dim)
        addSubview(resizeInput)
        controls = PanelChromeHost(state: chromeState)
        controls.frame = bounds
        addSubview(controls)
        chromeState.perform = { [weak self] action in self?.perform(action) }
        updateHint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func applyAppearance(_ value: Preferences, enhanced: Bool) {
        layer?.cornerRadius = value.cornerRadius
        frameView.layer?.cornerRadius = value.cornerRadius
        dim.layer?.cornerRadius = value.cornerRadius
        frameView.enhancement = .init(enabled: enhanced, contrast: value.contrastStrength, sharpness: value.sharpnessStrength)
        if showHints != value.showHoverHints { showHints = value.showHoverHints }
        if dimOnHover != value.dimOnHover { dimOnHover = value.dimOnHover }
        if hoverBlur != value.hoverBlur { hoverBlur = value.hoverBlur }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { owner?.pointerMoved(to: NSEvent.mouseLocation) }
    override func mouseExited(with event: NSEvent) { owner?.pointerMoved(to: NSEvent.mouseLocation) }
    override func layout() {
        super.layout()
        frameView.frame = bounds
        input.frame = frameView.frame
        dim.frame = bounds
        controls.frame = bounds
        let resize = chromeState.regions(in: bounds.size).first { $0.id == .resize }
        resizeInput.frame = resize?.frame ?? .zero
        resizeInput.isHidden = resize == nil
    }
    private func updateControls() {
        var value = chromeState.value
        value.hovered = hovered
        value.detection = detectionEnabled
        value.showHints = showHints
        value.clickToFocus = clickToFocus
        value.previewEnabled = previewEnabled
        value.message = statusMessage
        if let owner {
            value.fps = owner.fps
            value.changeDetection = owner.changeDetection
            value.threshold = owner.changeDetection ? owner.changeSeconds : owner.idleSeconds
            value.zoomed = owner.viewport.magnification > 1.001
        }
        if value != chromeState.value {
            if value.hovered != chromeState.value.hovered && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                withAnimation(.easeInOut(duration: 0.16)) { chromeState.value = value }
            } else { chromeState.value = value }
        }
    }
    func update(title: String, status: String, idle: Bool, detection: Bool, message: String?) {
        input.toolTip = title + " · " + status
        detectionEnabled = detection
        if chromeState.value.idle != idle { chromeState.value.idle = idle }
        statusMessage = message ?? (idle ? "内容暂时没有变化" : nil)
        updateHint()
        needsLayout = true
    }
    func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        updateHint()
        needsLayout = true
    }

    private func updateHint() {
        updateControls()
        dim.isHidden = !hovered || !dimOnHover
        input.toolTip = (clickToFocus ? "单击返回来源 · " : "") + "双击返回并关闭 · 轻按 \(triggerLabel) 隐藏 · 双击 \(triggerLabel) 切换自动隐藏 · Delete 关闭"
        needsLayout = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        target(at: convert(point, from: superview))
    }
    func target(atWindowPoint point: NSPoint) -> NSView? {
        target(at: convert(point, from: nil))
    }
    func cancelGesture() { input.cancelGesture() }
    func control(atWindowPoint point: NSPoint) -> PanelAction? {
        controls.region(at: controls.convert(point, from: nil))?.id
    }
    private func target(at local: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(local) else { return nil }
        layoutSubtreeIfNeeded()
        if controls.region(at: controls.convert(local, from: self))?.id == .resize { return resizeInput }
        return controls.hitTest(local) ?? input
    }
    private func perform(_ action: PanelAction) {
        switch action {
        case .close: owner?.close()
        case .frameRate: owner?.showFrameRateMenu()
        case .threshold: owner?.showThresholdMenu()
        case .detection: showDetectionMenu()
        case .resize: break
        }
    }
    @objc private func showDetectionMenu() {
        owner?.beginInteraction()
        defer { owner?.endInteraction() }
        guard let rect = chromeState.regions(in: bounds.size).first(where: { $0.id == .detection })?.frame else { return }
        owner?.detectionMenu().popUp(positioning: nil, at: CGPoint(x: rect.minX, y: rect.maxY + 4), in: self)
    }
}

final class PanelDimView: NSView {
    override var isFlipped: Bool { true }
    private let top = NSHostingView(rootView: PanelEdgeScrim(top: true, strength: Preferences().hoverBlur))
    private let bottom = NSHostingView(rootView: PanelEdgeScrim(top: false, strength: Preferences().hoverBlur))
    var strength: Double = Preferences().hoverBlur {
        didSet {
            guard strength != oldValue else { return }
            top.rootView = PanelEdgeScrim(top: true, strength: strength)
            bottom.rootView = PanelEdgeScrim(top: false, strength: strength)
        }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        top.sizingOptions = []
        bottom.sizingOptions = []
        addSubview(top)
        addSubview(bottom)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout()
        let height = min(52, bounds.height * 0.25)
        top.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        bottom.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class PanelInput: NSControl {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    weak var owner: CaptureSession?
    var onClick: (() -> Void)?
    private var start: CGPoint?
    private var moving = false
    private var clickGesture = PanelClickGesture()
    private var interacting = false
    private var doubleClick = false
    private var resetOnDoubleClick = false
    private var dragEvent: NSEvent?
    private var selection: CGRect?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        cancelGesture()
        dragEvent = event
        clickGesture.begin(at: event.locationInWindow)
        doubleClick = event.clickCount == 2
        resetOnDoubleClick = event.modifierFlags.contains(.command)
        owner?.beginInteraction()
        interacting = true
        if event.clickCount == 2 {
            moving = false
        } else if event.modifierFlags.contains(.command) {
            start = convert(event.locationInWindow, from: nil)
        } else { moving = true }
        guard interacting else { return }
        defer { cancelGesture() }
        // 在非激活面板内跟踪完整手势；移动和框选不会触发单击。
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: 0.1, mode: .eventTracking) { next, stop in
            guard self.interacting, window.isVisible, !window.ignoresMouseEvents else {
                stop.pointee = true
                return
            }
            guard let next else {
                if NSEvent.pressedMouseButtons & 1 == 0 { stop.pointee = true }
                return
            }
            if next.type == .leftMouseUp {
                self.mouseUp(with: next)
                stop.pointee = true
            } else {
                self.mouseDragged(with: next)
                if !self.interacting { stop.pointee = true }
            }
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard clickGesture.move(to: event.locationInWindow) else { return }
        if moving {
            moving = false
            defer { cancelGesture() }
            if let dragEvent { window?.performDrag(with: dragEvent) }
            return
        }
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { cancelGesture() }
        if clickGesture.end(at: event.locationInWindow), start == nil {
            if doubleClick { owner?.doubleClicked(reset: resetOnDoubleClick) }
            else { onClick?() }
        }
        guard let selection, selection.width >= 6, selection.height >= 6, let owner else { return }
        owner.setViewport(owner.viewport.selecting(CGRect(x: selection.minX / bounds.width,
            y: selection.minY / bounds.height, width: selection.width / bounds.width, height: selection.height / bounds.height)))
    }

    func cancelGesture() {
        clickGesture.cancel()
        start = nil; moving = false; dragEvent = nil; selection = nil
        needsDisplay = true
        if interacting { interacting = false; owner?.endInteraction() }
    }
    override func scrollWheel(with event: NSEvent) {
        guard let owner else { return }
        if event.modifierFlags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            owner.setViewport(owner.viewport.zoomed(by: exp(-Double(event.scrollingDeltaY) * 0.015),
                around: CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)))
        } else {
            let multiplier = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
            owner.setViewport(owner.viewport.panned(x: -Double(event.scrollingDeltaX) * multiplier / bounds.width,
                                                    y: -Double(event.scrollingDeltaY) * multiplier / bounds.height))
        }
    }
    override func magnify(with event: NSEvent) {
        guard let owner else { return }
        let point = convert(event.locationInWindow, from: nil)
        owner.setViewport(owner.viewport.zoomed(by: max(0.1, 1 + Double(event.magnification)),
            around: CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)))
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = owner?.makeMenu() else { return }
        owner?.beginInteraction()
        defer { owner?.endInteraction() }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func draw(_ dirtyRect: NSRect) {
        if let selection {
            NSColor.systemMint.withAlphaComponent(0.18).setFill(); selection.fill()
            NSColor.systemMint.setStroke(); NSBezierPath(rect: selection).stroke()
        }
    }
}
#endif
