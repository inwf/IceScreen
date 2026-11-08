#if os(macOS)
import AppKit
import IceCore

@MainActor
final class QuickLookPreview {
    private var panel: FloatingPanel?
    private var pipeline: CapturePipeline?
    private var frameView: FrameView?
    private var openedAt: TimeInterval?
    private var mouseGlobal: Any?
    private var mouseLocal: Any?
    private(set) var sourceID: CGWindowID?
    var isVisible: Bool { panel != nil }

    func press(_ session: CaptureSession) {
        if isVisible { close(); return }
        openedAt = ProcessInfo.processInfo.systemUptime
        sourceID = session.source.windowID
        let screen = session.panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let sourceSize = session.source.frame.size
        let ratio = sourceSize.width / sourceSize.height
        let width = min(sourceSize.width, screen.width - 48, (screen.height - 48) * ratio)
        let size = CGSize(width: width, height: width / ratio)
        let rect = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                          width: size.width, height: size.height)
        let window = FloatingPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        window.backgroundColor = .windowBackgroundColor
        let view = FrameView(frame: CGRect(origin: .zero, size: size))
        window.contentView = view
        window.orderFrontRegardless()
        let capture = CapturePipeline(source: session.source)
        capture.output.mailbox.deliver = { [weak view] in view?.display($0) }
        capture.onError = { [weak self] _ in self?.close() }
        capture.configure(viewport: .full, sourceSize: sourceSize, size: size, scale: window.backingScaleFactor, fps: session.fps)
        capture.setRunning(true)
        panel = window
        frameView = view
        pipeline = capture
        mouseGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        mouseLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let insidePreview = event.window === self?.panel
            self?.close()
            return insidePreview ? nil : event
        }
    }

    func release() {
        guard let openedAt, ProcessInfo.processInfo.systemUptime - openedAt >= 0.25 else { return }
        close()
    }

    func close() {
        pipeline?.close(); pipeline = nil
        frameView?.releaseFrame(); frameView = nil
        panel?.close(); panel = nil
        openedAt = nil; sourceID = nil
        if let mouseGlobal { NSEvent.removeMonitor(mouseGlobal); self.mouseGlobal = nil }
        if let mouseLocal { NSEvent.removeMonitor(mouseLocal); self.mouseLocal = nil }
    }
}
#endif
