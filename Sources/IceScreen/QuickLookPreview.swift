#if os(macOS)
import AppKit
import IceCore

@MainActor
final class QuickLookPreview {
    private var panel: FloatingPanel?
    private var pipeline: CapturePipeline?
    private var frameView: FrameView?
    private var gesture = PreviewGesture()
    private var generation = 0
    private weak var session: CaptureSession?
    private var mouseGlobal: Any?
    private var mouseLocal: Any?
    private(set) var sourceID: CGWindowID?
    var isPresented: Bool { gesture.isPresented }
    var onError: ((Error) -> Void)?

    func press(_ session: CaptureSession) {
        guard gesture.press(at: ProcessInfo.processInfo.systemUptime) else { close(); return }
        schedulePresentation(session)
    }

    func show(_ session: CaptureSession) {
        close()
        gesture.present()
        schedulePresentation(session)
    }

    private func schedulePresentation(_ session: CaptureSession) {
        generation += 1
        let request = generation
        sourceID = session.source.windowID
        self.session = session
        session.beginInteraction()
        DispatchQueue.main.async { [weak self, weak session] in
            guard let self, let session, self.generation == request, self.gesture.isPresented else { return }
            self.present(session)
        }
    }

    private func present(_ session: CaptureSession) {
        let screen = session.panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let sourceSize = session.currentSourceSize
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
        window.isOpaque = false
        window.backgroundColor = .clear
        let view = FrameView(frame: CGRect(origin: .zero, size: size))
        window.contentView = view
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true
        window.orderFrontRegardless()
        let capture = CapturePipeline(source: session.source)
        capture.output.mailbox.deliver = { [weak view] in view?.display($0) }
        capture.onError = { [weak self] error in
            self?.close()
            self?.onError?(error)
        }
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
        gesture.release(at: ProcessInfo.processInfo.systemUptime)
        if !gesture.isPresented { close() }
    }

    func close() {
        generation += 1
        gesture.close()
        pipeline?.close(); pipeline = nil
        frameView?.releaseFrame(); frameView = nil
        panel?.close(); panel = nil
        sourceID = nil
        session?.endInteraction(); session = nil
        if let mouseGlobal { NSEvent.removeMonitor(mouseGlobal); self.mouseGlobal = nil }
        if let mouseLocal { NSEvent.removeMonitor(mouseLocal); self.mouseLocal = nil }
    }
}
#endif
