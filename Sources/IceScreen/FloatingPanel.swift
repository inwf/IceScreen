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
    @Published private(set) var paused = false
    @Published private(set) var hidden = false
    @Published private(set) var autoHidden = false
    @Published private(set) var idle = false
    @Published var autoHide: Bool { didSet { if !autoHide { setAutoHidden(false) }; updateStatus() } }
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
    private var closeDeadline: TimeInterval?
    private var lastActivity = ProcessInfo.processInfo.systemUptime
    private var closed = false
    private var systemSuspended = false
    private var userIsResizing = false
    private var sourceSize: CGSize
    private var lastGeometryCheck: TimeInterval = 0

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
        let width = min(preferences.preferredWidth, screen.width * 0.8, (screen.height * 0.8 - 32) * ratio)
        let size = CGSize(width: width, height: width / ratio + 32)
        let rect = CGRect(x: screen.maxX - width - 24 - CGFloat(offset % 5) * 28,
                          y: screen.maxY - size.height - 24 - CGFloat(offset % 5) * 28,
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
        panel.minSize = CGSize(width: 160, height: 92)
        panel.contentView = surface
        panel.delegate = self
        surface.owner = self
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
            self.paused = true
            self.updateStatus()
        }
        updateStatus()
    }

    func start() {
        panel.orderFrontRegardless()
        configure()
        syncRunning()
    }

    private func configure() {
        surface.layoutSubtreeIfNeeded()
        pipeline.configure(viewport: viewport, sourceSize: sourceSize, size: surface.frameView.bounds.size,
                           scale: panel.backingScaleFactor, fps: fps)
    }

    private func syncRunning() {
        pipeline.setRunning(!closed && !paused && !hidden && !autoHidden && !systemSuspended)
    }

    func suspend(_ value: Bool) {
        systemSuspended = value
        if !value { lastActivity = ProcessInfo.processInfo.systemUptime }
        syncRunning()
    }

    func setViewport(_ value: Viewport) {
        viewport = value
        let ratio = (sourceSize.width * value.rect.width) / (sourceSize.height * value.rect.height)
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = frame.width / ratio + 32
        if let screen = panel.screen, frame.height > screen.visibleFrame.height {
            frame.size.height = screen.visibleFrame.height
            frame.size.width = (frame.height - 32) * ratio
        }
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true)
        configure()
        lastActivity = ProcessInfo.processInfo.systemUptime
        idle = false
        updateStatus()
    }

    func setFPS(_ value: Int) {
        guard Preferences.frameRates.contains(value) else { return }
        fps = value
        configure()
        updateStatus()
    }

    @objc func cycleFPS() {
        let rates = Preferences.frameRates
        let next = rates[((rates.firstIndex(of: fps) ?? 0) + 1) % rates.count]
        onFrameRate?(bundleID, next)
    }

    @objc func togglePaused() {
        paused.toggle()
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
        hidden.toggle()
        closeDeadline = hidden ? ProcessInfo.processInfo.systemUptime + 60 : nil
        if hidden {
            panel.orderOut(nil)
            surface.frameView.releaseFrame()
        } else {
            autoHidden = false
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
        if autoHide && inside != autoHidden { setAutoHidden(inside) }
        if !inside && autoHidden { setAutoHidden(false) }
    }

    private func setAutoHidden(_ value: Bool) {
        guard value != autoHidden else { return }
        autoHidden = value
        if !value { lastActivity = ProcessInfo.processInfo.systemUptime }
        panel.ignoresMouseEvents = value
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = value ? 0 : 1
        }
        syncRunning()
        if value { surface.frameView.releaseFrame() }
        updateStatus()
    }

    func tick(at now: TimeInterval) {
        if let closeDeadline, now >= closeDeadline { close(); return }
        if !systemSuspended, now - lastGeometryCheck >= 2 {
            lastGeometryCheck = now
            checkSourceGeometry()
        }
        guard idleDetection, !paused, !hidden, !autoHidden, !systemSuspended else { return }
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
        if sourceSize != frame.size { sourceSize = frame.size; setViewport(viewport) }
    }

    func updateStatus() {
        surface.update(title: title, status: status, idle: idle, detection: idleDetection,
                       message: failure ?? (paused ? "捕获已暂停" : nil))
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
    func windowWillStartLiveResize(_ notification: Notification) { userIsResizing = true }
    func windowDidEndLiveResize(_ notification: Notification) {
        userIsResizing = false
        onResize?(Double(panel.frame.width))
        configure()
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let ratio = (sourceSize.width * viewport.rect.width) / (sourceSize.height * viewport.rect.height)
        if abs(frameSize.height - panel.frame.height) * ratio > abs(frameSize.width - panel.frame.width) {
            return CGSize(width: (frameSize.height - 32) * ratio, height: frameSize.height)
        }
        return CGSize(width: frameSize.width, height: frameSize.width / ratio + 32)
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
        let fpsMenu = NSMenu()
        for rate in Preferences.frameRates {
            let item = NSMenuItem(title: "\(rate) FPS", action: #selector(chooseFPS(_:)), keyEquivalent: "")
            item.target = self; item.tag = rate; item.state = fps == rate ? .on : .off
            fpsMenu.addItem(item)
        }
        let fpsItem = NSMenuItem(title: "应用帧率", action: nil, keyEquivalent: "")
        fpsItem.submenu = fpsMenu
        menu.addItem(fpsItem)
        menu.addItem(.separator())
        add("鼠标移入时自动隐藏", #selector(toggleAutoHide), checked: autoHide)
        add("检测内容空闲", #selector(toggleIdle), checked: idleDetection)
        add("增强对比度和清晰度", #selector(toggleEnhanced), checked: enhanced)
        menu.addItem(.separator())
        add("暂时隐藏", #selector(toggleHidden))
        add("关闭浮窗", #selector(close))
        return menu
    }
}

@MainActor
final class PanelSurface: NSView {
    override var isFlipped: Bool { true }
    let frameView = FrameView(frame: .zero)
    private let input = PanelInput(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusDot = NSButton()
    private let menuButton = NSButton()
    private let closeButton = NSButton()
    weak var owner: CaptureSession? { didSet { input.owner = owner } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.16, alpha: 1).cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(frameView)
        addSubview(input)
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        for (button, symbol, label, action) in [
            (statusDot, "circle.fill", "切换空闲检测", #selector(toggleIdle)),
            (menuButton, "ellipsis", "浮窗设置", #selector(showMenu)),
            (closeButton, "xmark", "关闭浮窗", #selector(closePanel))
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.isBordered = false
            button.contentTintColor = .white
            button.target = self; button.action = action; button.toolTip = label
            addSubview(button)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() {
        super.layout()
        let height = max(1, bounds.height - 32)
        frameView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        input.frame = frameView.frame
        statusDot.frame = CGRect(x: 8, y: height + 7, width: 18, height: 18)
        titleLabel.frame = CGRect(x: 32, y: height + 9, width: max(20, bounds.width - 98), height: 16)
        menuButton.frame = CGRect(x: bounds.width - 60, y: height + 5, width: 26, height: 22)
        closeButton.frame = CGRect(x: bounds.width - 30, y: height + 5, width: 24, height: 22)
    }
    func update(title: String, status: String, idle: Bool, detection: Bool, message: String?) {
        titleLabel.stringValue = title
        titleLabel.toolTip = status
        statusDot.contentTintColor = idle ? .systemOrange : (detection ? .systemMint : .gray)
        statusDot.toolTip = status + " · 点击切换空闲检测"
        input.message = message ?? (idle ? "内容暂时没有变化" : nil)
    }
    @objc private func toggleIdle() { owner?.toggleIdle() }
    @objc private func closePanel() { owner?.close() }
    @objc private func showMenu() {
        owner?.makeMenu().popUp(positioning: nil, at: CGPoint(x: bounds.width - 60, y: bounds.height), in: self)
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

@MainActor
final class PanelInput: NSView {
    override var isFlipped: Bool { true }
    weak var owner: CaptureSession?
    private var start: CGPoint?
    private var selection: CGRect?
    var message: String? { didSet { needsDisplay = true } }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            if event.modifierFlags.contains(.command) { owner?.resetZoom() } else { owner?.focusSource() }
        } else if event.modifierFlags.contains(.command) {
            start = convert(event.locationInWindow, from: nil)
        } else { window?.performDrag(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { start = nil; selection = nil; needsDisplay = true }
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
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = owner?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func draw(_ dirtyRect: NSRect) {
        if let selection {
            NSColor.systemMint.withAlphaComponent(0.18).setFill(); selection.fill()
            NSColor.systemMint.setStroke(); NSBezierPath(rect: selection).stroke()
        }
        if let message {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white
            ]
            let size = message.size(withAttributes: attributes)
            let rect = CGRect(x: 10, y: 10, width: size.width + 18, height: 26)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            message.draw(at: CGPoint(x: 19, y: 16), withAttributes: attributes)
        }
    }
}
#endif
