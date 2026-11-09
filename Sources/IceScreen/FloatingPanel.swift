#if os(macOS)
import AppKit
import ScreenCaptureKit
import IceCore

@MainActor
final class CaptureSession: NSObject, ObservableObject, Identifiable, NSWindowDelegate {
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
    var onFocus: ((SCWindow) -> Bool)?
    var onPreview: (() -> Void)?
    var onFrameRate: ((String, Int) -> Void)?
    var onResize: ((Double) -> Void)?
    var onChange: (() -> Void)?
    private var resizeTask: Task<Void, Never>?
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
        surface.layer?.cornerRadius = value.cornerRadius
        surface.showHints = value.showHoverHints
        surface.dimOnHover = value.dimOnHover
        surface.hoverBlur = value.hoverBlur
        panelOpacity = value.panelOpacity
        if !autoHidden { panel.alphaValue = panelOpacity }
        triggerLabel = value.triggerModifier.display
        surface.triggerLabel = triggerLabel
        panel.collectionBehavior = value.showOnFullscreenSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary] : [.canJoinAllSpaces, .stationary]
    }

    func sourceFocusChanged(windowID: CGWindowID?, behavior: SourceFocusBehavior) {
        let focused = windowID == source.windowID
        if !focused { preserveOnSourceFocus = false }
        if focused && behavior == .close && !preserveOnSourceFocus { close(); return }
        sourcePaused = focused && behavior == .pause
        syncRunning()
        updateStatus()
    }

    func clicked() {
        guard clickToFocus, !closed else { return }
        focusSource()
    }

    func doubleClicked(reset: Bool) {
        if reset { resetZoom() }
        else if onFocus?(source) == true { close() }
    }

    func showFrameRateMenu() {
        beginInteraction()
        defer { endInteraction() }
        let point = surface.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        frameRateMenu().popUp(positioning: nil, at: point, in: surface)
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
        preserveOnSourceFocus = true
        if onFocus?(source) != true { preserveOnSourceFocus = false }
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
    private let statusDot = PanelButton()
    private let menuButton = PanelButton()
    private let closeButton = PanelButton()
    private let focusButton = PanelButton()
    private let previewButton = PanelButton()
    private let controls = PanelControlsView()
    private var buttonHosts: [PanelButton: PanelGlassControl] = [:]
    private var controlsContainer: NSView!
    private let hint = PanelHintView()
    private let dim = PanelDimView()
    private var hintTask: Task<Void, Never>?
    private var hintsExpired = false
    private var statusMessage: String?
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var detectionEnabled = false
    var onContentClick: (() -> Void)? { didSet { input.onClick = onContentClick } }
    var showHints = true { didSet { updateHint() } }
    var triggerLabel = "fn" { didSet { updateHint() } }
    var clickToFocus = true { didSet { updateHint() } }
    var previewEnabled = true { didSet { needsLayout = true; updateHint() } }
    var dimOnHover = true { didSet { updateHint() } }
    var hoverBlur: Double = 0.35 { didSet { dim.strength = hoverBlur } }
    weak var owner: CaptureSession? { didSet { input.owner = owner } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(frameView)
        addSubview(input)
        addSubview(dim)
        addSubview(hint)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView(frame: bounds)
            container.contentView = controls
            container.spacing = 0
            controlsContainer = container
        } else { controlsContainer = controls }
        #else
        controlsContainer = controls
        #endif
        addSubview(controlsContainer)
        for (button, symbol, label, action) in [
            (statusDot, "waveform.path", "内容检测", #selector(showDetectionMenu)),
            (menuButton, "ellipsis", "浮窗设置", #selector(showMenu)),
            (closeButton, "xmark", "关闭浮窗", #selector(closePanel)),
            (focusButton, "macwindow", "定位来源窗口", #selector(focusSource)),
            (previewButton, "arrow.up.left.and.arrow.down.right", "预览来源窗口 · Space", #selector(showPreview))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly
            button.setButtonType(.momentaryChange)
            button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: .medium)
            button.contentTintColor = .labelColor
            button.setAccessibilityLabel(label)
            button.target = self; button.action = action; button.toolTip = label
            let host = PanelGlassControl(button: button)
            buttonHosts[button] = host
            controls.addSubview(host)
        }
        statusDot.title = "检测"
        statusDot.imagePosition = .imageLeading
        setHovered(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
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
        controlsContainer.frame = bounds
        controls.frame = bounds
        let compact = bounds.width < 180 || bounds.height < 100
        place(closeButton, CGRect(x: 8, y: 8, width: 32, height: 32), hidden: !hovered)
        place(statusDot, CGRect(x: bounds.width - 96, y: 8, width: 88, height: 32),
              hidden: compact || (!hovered && !detectionEnabled))
        if compact {
            place(menuButton, CGRect(x: bounds.width - 40, y: 8, width: 32, height: 32), hidden: !hovered)
        } else {
            place(menuButton, CGRect(x: bounds.width - 40, y: bounds.height - 40, width: 32, height: 32), hidden: !hovered)
        }
        place(focusButton, CGRect(x: 8, y: bounds.height - 40, width: 32, height: 32), hidden: !hovered || compact)
        place(previewButton, CGRect(x: bounds.width - 80, y: bounds.height - 40, width: 32, height: 32),
              hidden: !hovered || compact || !previewEnabled)
        let hintWidth = min(300, max(0, bounds.width - 32))
        hint.frame = CGRect(x: (bounds.width - hintWidth) / 2, y: (bounds.height - 64) / 2, width: hintWidth, height: 64)
        hint.isHidden = bounds.width < 210 || bounds.height < 170 || hint.text.isEmpty
    }
    private func place(_ button: PanelButton, _ rect: CGRect, hidden: Bool) {
        guard let host = buttonHosts[button] else { return }
        host.frame = rect
        host.isHidden = hidden
        host.needsLayout = true
    }
    func update(title: String, status: String, idle: Bool, detection: Bool, message: String?) {
        input.toolTip = title + " · " + status
        detectionEnabled = detection
        statusDot.title = idle ? "已空闲" : (detection ? "检测中" : "检测")
        statusDot.contentTintColor = idle ? .systemOrange : .labelColor
        statusDot.toolTip = "内容检测：" + (detection ? (idle ? "内容已停止变化" : "正在监测") : "尚未启用") + "。点击选择空闲提醒、变化提醒或细微变化。"
        statusDot.setAccessibilityValue(statusDot.title)
        statusMessage = message ?? (idle ? "内容暂时没有变化" : nil)
        updateHint()
        needsLayout = true
    }
    func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        hintsExpired = false
        hintTask?.cancel()
        if value {
            hintTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.hintsExpired = true
                self?.updateHint()
            }
        }
        updateHint()
        needsLayout = true
    }

    private func updateHint() {
        if let statusMessage { hint.text = statusMessage }
        else if hovered && showHints && !hintsExpired {
            let click = clickToFocus ? "单击定位 · 双击定位并关闭" : "双击定位并关闭"
            hint.text = click + "\n⌘ 拖动缩放" + (previewEnabled ? " · Space 预览" : "")
        } else { hint.text = "" }
        dim.isHidden = !hovered || !dimOnHover
        input.toolTip = (clickToFocus ? "单击定位 · " : "") + "双击定位并关闭 · 双击 \(triggerLabel) 切换自动隐藏"
        needsLayout = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        target(at: convert(point, from: superview))
    }
    func target(atWindowPoint point: NSPoint) -> NSView? {
        target(at: convert(point, from: nil))
    }
    private func target(at local: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(local) else { return nil }
        layoutSubtreeIfNeeded()
        for button in [closeButton, statusDot, focusButton, previewButton, menuButton]
            where buttonHosts[button]?.isHidden == false {
            let buttonPoint = button.convert(local, from: self)
            guard button.bounds.contains(buttonPoint) else { continue }
            return button
        }
        return input
    }
    @objc private func showDetectionMenu() {
        owner?.beginInteraction()
        defer { owner?.endInteraction() }
        let rect = statusDot.convert(statusDot.bounds, to: self)
        owner?.detectionMenu().popUp(positioning: nil, at: CGPoint(x: rect.minX, y: rect.maxY + 4), in: self)
    }
    @objc private func closePanel() { owner?.close() }
    @objc private func focusSource() { owner?.focusSource() }
    @objc private func showPreview() { owner?.showPreview() }
    @objc private func showMenu() {
        owner?.beginInteraction()
        defer { owner?.endInteraction() }
        let rect = menuButton.convert(menuButton.bounds, to: self)
        owner?.makeMenu().popUp(positioning: nil, at: CGPoint(x: rect.minX, y: rect.maxY + 4), in: self)
    }
}

final class PanelButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
}

final class PanelGlassControl: NSView {
    let button: PanelButton
    private let effect: NSView

    init(button: PanelButton) {
        self.button = button
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
            button.isBordered = true
            effect = button
        } else {
            effect = Self.legacyEffect(button)
        }
        #else
        effect = Self.legacyEffect(button)
        #endif
        super.init(frame: .zero)
        addSubview(effect)
    }

    private static func legacyEffect(_ button: PanelButton) -> NSView {
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 16
        material.layer?.masksToBounds = true
        material.addSubview(button)
        return material
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout()
        effect.frame = bounds
        if effect !== button { button.frame = effect.bounds }
    }
}

final class PanelControlsView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

final class PanelHintView: NSVisualEffectView {
    private let label = NSTextField(wrappingLabelWithString: "")
    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout()
        label.preferredMaxLayoutWidth = max(0, bounds.width - 20)
        let height = min(bounds.height - 12, label.fittingSize.height)
        label.frame = NSRect(x: 10, y: (bounds.height - height) / 2, width: bounds.width - 20, height: height)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PanelDimView: NSView {
    private let top = CAGradientLayer()
    private let bottom = CAGradientLayer()
    var strength: Double = 0.35 { didSet { updateColors() } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        top.startPoint = CGPoint(x: 0.5, y: 1)
        top.endPoint = CGPoint(x: 0.5, y: 0)
        bottom.startPoint = CGPoint(x: 0.5, y: 0)
        bottom.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(top)
        layer?.addSublayer(bottom)
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func updateColors() {
        let colors = [NSColor.black.withAlphaComponent(strength * 0.4).cgColor,
                      NSColor.black.withAlphaComponent(0).cgColor]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        top.colors = colors
        bottom.colors = colors
        CATransaction.commit()
    }
    override func layout() {
        super.layout()
        let height = min(52, bounds.height * 0.25)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        top.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        bottom.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class PanelInput: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    weak var owner: CaptureSession?
    var onClick: (() -> Void)?
    private var start: CGPoint?
    private var moving = false
    private var clickGesture = PanelClickGesture()
    private var interacting = false
    private var doubleClick = false
    private var dragEvent: NSEvent?
    private var selection: CGRect?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        cancelGesture()
        dragEvent = event
        clickGesture.begin(at: event.locationInWindow)
        doubleClick = event.clickCount == 2
        owner?.beginInteraction()
        interacting = true
        if event.clickCount == 2 {
            owner?.doubleClicked(reset: event.modifierFlags.contains(.command))
        } else if event.modifierFlags.contains(.command) {
            start = convert(event.locationInWindow, from: nil)
        } else { moving = true }
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
        if clickGesture.end(at: event.locationInWindow), !doubleClick, start == nil { onClick?() }
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
