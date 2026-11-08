#if os(macOS)
import AppKit
import ScreenCaptureKit
import IceCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

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
    @Published var idleDetection: Bool { didSet {
        pipeline.output.configureIdle(idleDetection)
        lastActivity = ProcessInfo.processInfo.systemUptime
        idle = false
        updateStatus()
    } }
    @Published var enhanced: Bool { didSet { surface.frameView.enhanced = enhanced } }
    @Published private(set) var failure: String?
    var idleSeconds: Double
    var onClose: ((CaptureSession) -> Void)?
    var onFocus: ((SCWindow) -> Void)?
    var onFrameRate: ((String, Int) -> Void)?
    var onResize: ((Double) -> Void)?
    var onChange: (() -> Void)?
    private var resizeTask: Task<Void, Never>?
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var closed = false
    private var userIsResizing = false
    private var sourceSize: CGSize
    private var lastGeometryCheck: TimeInterval = 0
    private var sourcePaused = false
    private var clickToFocus = false
    private var clickTask: Task<Void, Never>?
    private var triggerLabel = "fn"

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
        enhanced = preferences.enhanceContrast
        idleSeconds = preferences.idleSeconds
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
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.minSize = CGSize(width: 80, height: 40)
        panel.contentAspectRatio = CGSize(width: ratio, height: 1)
        panel.contentView = surface
        panel.delegate = self
        surface.owner = self
        applyPreferences(preferences)
        surface.frameView.enhanced = enhanced
        pipeline.output.mailbox.deliver = { [weak surface] buffer in surface?.frameView.display(buffer) }
        pipeline.output.onActivity = { [weak self] in
            guard let self else { return }
            self.lastActivity = ProcessInfo.processInfo.systemUptime
            if self.idle { self.idle = false; self.updateStatus() }
        }
        pipeline.output.configureIdle(idleDetection)
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
        pipeline.setRunning(!closed && !sourcePaused && visibility.shouldCapture)
    }

    func suspend(_ value: Bool, display: Bool) {
        if display { visibility.displaySleeping = value } else { visibility.systemSleeping = value }
        if !value { lastActivity = ProcessInfo.processInfo.systemUptime }
        syncRunning()
    }

    func setViewport(_ value: Viewport) {
        guard viewport != value else { return }
        let oldRatio = viewport.rect.width / viewport.rect.height
        viewport = value
        if abs(oldRatio - value.rect.width / value.rect.height) > 0.00001 { fitPanelToContent() }
        configure()
        lastActivity = ProcessInfo.processInfo.systemUptime
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
        clickToFocus = value.clickToFocus
        surface.layer?.cornerRadius = value.cornerRadius
        surface.showHints = value.showHoverHints
        triggerLabel = value.triggerModifier.display
        surface.triggerLabel = triggerLabel
        panel.collectionBehavior = value.showOnFullscreenSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary] : [.canJoinAllSpaces, .stationary]
    }

    func sourceFocusChanged(windowID: CGWindowID?, behavior: SourceFocusBehavior) {
        let focused = windowID == source.windowID
        if focused && behavior == .close { close(); return }
        sourcePaused = focused && behavior == .pause
        syncRunning()
        updateStatus()
    }

    func clicked() {
        guard clickToFocus else { return }
        clickTask?.cancel()
        clickTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval)) } catch { return }
            self?.focusSource()
        }
    }

    func doubleClicked(reset: Bool) {
        clickTask?.cancel()
        if reset { resetZoom() }
        else { focusSource(); close() }
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
        lastActivity = ProcessInfo.processInfo.systemUptime
        syncRunning()
        updateStatus()
    }

    @objc func toggleIdle() { idleDetection.toggle() }
    @objc func toggleEnhanced() { enhanced.toggle(); updateStatus() }
    @objc func toggleAutoHide() { autoHide.toggle() }
    @objc func focusSource() { onFocus?(source) }
    @objc func resetZoom() { setViewport(.full) }
    @objc func zoomIn() { setViewport(viewport.zoomed(by: 1.25)) }
    @objc func zoomOut() { setViewport(viewport.zoomed(by: 0.8)) }

    @objc func toggleHidden() {
        visibility.toggleManual(at: ProcessInfo.processInfo.systemUptime)
        if hidden {
            panel.orderOut(nil)
            surface.frameView.releaseFrame()
        } else {
            panel.alphaValue = 1
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            lastActivity = ProcessInfo.processInfo.systemUptime
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
        if !value { lastActivity = ProcessInfo.processInfo.systemUptime }
        panel.ignoresMouseEvents = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = value ? 0 : 1
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

    func beginInteraction() { visibility.interacting = true }
    func endInteraction() {
        visibility.interacting = false
        pointerMoved(to: NSEvent.mouseLocation)
    }

    func tick(at now: TimeInterval) {
        if visibility.isExpired(at: now) { close(); return }
        if !visibility.systemSleeping, !visibility.displaySleeping, now - lastGeometryCheck >= 2 {
            lastGeometryCheck = now
            checkSourceGeometry()
        }
        guard idleDetection, visibility.shouldCapture, !sourcePaused else { return }
        let value = now - lastActivity >= idleSeconds
        if idle != value { idle = value; updateStatus() }
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
        surface.update(title: title, status: status, idle: idle, detection: idleDetection,
                       message: failure ?? (paused || sourcePaused ? "捕获已暂停" : nil))
        onChange?()
    }

    @objc func close() {
        guard !closed else { return }
        closed = true
        resizeTask?.cancel()
        clickTask?.cancel()
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

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, checked: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let checked { item.state = checked ? .on : .off }
            menu.addItem(item)
        }
        add("定位来源窗口", #selector(focusSource))
        add(paused ? "继续捕获" : "暂停捕获", #selector(togglePaused))
        add("恢复完整画面", #selector(resetZoom))
        let fpsItem = NSMenuItem(title: "应用帧率", action: nil, keyEquivalent: "")
        fpsItem.submenu = frameRateMenu()
        menu.addItem(fpsItem)
        menu.addItem(.separator())
        add("鼠标移入时自动隐藏", #selector(toggleAutoHide), checked: autoHide)
        add("检测内容空闲", #selector(toggleIdle), checked: idleDetection)
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
    let frameView = FrameView(frame: .zero)
    private let input = PanelInput(frame: .zero)
    private let statusDot = PanelButton()
    private let menuButton = PanelButton()
    private let closeButton = PanelButton()
    private var hovered = false
    private var detectionEnabled = false
    var showHints = true { didSet { input.showHints = showHints && hovered } }
    var triggerLabel = "fn" { didSet { input.triggerLabel = triggerLabel } }
    private var statusContainer: NSView!
    private var menuContainer: NSView!
    private var closeContainer: NSView!
    weak var owner: CaptureSession? { didSet { input.owner = owner } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.16, alpha: 1).cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(frameView)
        addSubview(input)
        for (button, symbol, label, action) in [
            (statusDot, "circle.fill", "切换空闲检测", #selector(toggleIdle)),
            (menuButton, "ellipsis", "浮窗设置", #selector(showMenu)),
            (closeButton, "xmark", "关闭浮窗", #selector(closePanel))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.isBordered = false
            button.contentTintColor = .labelColor
            button.target = self; button.action = action; button.toolTip = label
        }
        statusContainer = makeControlContainer(statusDot)
        menuContainer = makeControlContainer(menuButton)
        closeContainer = makeControlContainer(closeButton)
        for container in [statusContainer!, menuContainer!, closeContainer!] { addSubview(container) }
        setHovered(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout()
        frameView.frame = bounds
        input.frame = frameView.frame
        closeContainer.frame = CGRect(x: 8, y: 8, width: 28, height: 28)
        menuContainer.frame = CGRect(x: 42, y: 8, width: 28, height: 28)
        statusContainer.frame = CGRect(x: bounds.width - 36, y: 8, width: 28, height: 28)
    }
    func update(title: String, status: String, idle: Bool, detection: Bool, message: String?) {
        input.toolTip = title + " · " + status
        detectionEnabled = detection
        statusDot.contentTintColor = idle ? .systemOrange : (detection ? .systemMint : .gray)
        statusDot.toolTip = status + " · 点击切换空闲检测"
        input.message = message ?? (idle ? "内容暂时没有变化" : nil)
        setHovered(hovered)
    }
    func setHovered(_ value: Bool) {
        hovered = value
        input.showHints = showHints && value
        closeContainer.isHidden = !value
        menuContainer.isHidden = !value
        statusContainer.isHidden = !value && !detectionEnabled
    }

    private func makeControlContainer(_ button: NSButton) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: .zero)
            glass.style = .regular
            glass.cornerRadius = 14
            glass.contentView = button
            return glass
        }
        #endif
        let material = NSVisualEffectView(frame: .zero)
        material.material = .hudWindow
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.masksToBounds = true
        button.autoresizingMask = [.width, .height]
        material.addSubview(button)
        return material
    }
    @objc private func toggleIdle() { owner?.toggleIdle() }
    @objc private func closePanel() { owner?.close() }
    @objc private func showMenu() {
        owner?.beginInteraction()
        defer { owner?.endInteraction() }
        owner?.makeMenu().popUp(positioning: nil, at: CGPoint(x: 38, y: 36), in: self)
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class PanelButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelInput: NSView {
    override var isFlipped: Bool { true }
    weak var owner: CaptureSession?
    private var start: CGPoint?
    private var moving = false
    private var dragged = false
    private var doubleClick = false
    private var dragEvent: NSEvent?
    private var selection: CGRect?
    var message: String? { didSet { needsDisplay = true } }
    var showHints = false { didSet { if showHints != oldValue { needsDisplay = true } } }
    var triggerLabel = "fn" { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        start = nil; moving = false; selection = nil
        dragEvent = event
        dragged = false
        doubleClick = event.clickCount == 2
        if event.clickCount == 2 {
            owner?.doubleClicked(reset: event.modifierFlags.contains(.command))
        } else if event.modifierFlags.contains(.command) {
            owner?.beginInteraction()
            start = convert(event.locationInWindow, from: nil)
        } else { moving = true }
    }
    override func mouseDragged(with event: NSEvent) {
        dragged = true
        if moving {
            moving = false
            owner?.beginInteraction()
            defer { owner?.endInteraction() }
            if let dragEvent { window?.performDrag(with: dragEvent) }
            dragEvent = nil
            return
        }
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { start = nil; moving = false; dragEvent = nil; selection = nil; needsDisplay = true; owner?.endInteraction() }
        if !dragged, !doubleClick, start == nil { owner?.clicked() }
        guard let selection, selection.width >= 6, selection.height >= 6, let owner else { return }
        owner.setViewport(owner.viewport.selecting(CGRect(x: selection.minX / bounds.width,
            y: selection.minY / bounds.height, width: selection.width / bounds.width, height: selection.height / bounds.height)))
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
        if let message = message ?? (showHints ? "⌘ 拖动缩放 · 双击定位并关闭 · \(triggerLabel) 双击切换自动隐藏" : nil) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white
            ]
            let size = message.size(withAttributes: attributes)
            let rect = CGRect(x: 10, y: max(10, bounds.height - 36), width: min(bounds.width - 20, size.width + 18), height: 26)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            (message as NSString).draw(in: rect.insetBy(dx: 9, dy: 6), withAttributes: attributes)
        }
    }
}
#endif
