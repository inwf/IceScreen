#if os(macOS)
import AppKit
import IceCore

@MainActor
final class QuickLookPreview {
    private var presentation: PreviewPresentation?
    private var dismissing: PreviewPresentation?
    private var pipeline: CapturePipeline?
    private var gesture = PreviewGesture()
    private var mediaGesture = MediaSpaceGesture()
    private var mediaHoldTask: Task<Void, Never>?
    private weak var mediaSession: CaptureSession?
    private var generation = 0
    private weak var session: CaptureSession?
    private var mouseGlobal: Any?
    private var mouseLocal: Any?
    private(set) var sourceID: CGWindowID?
    var isPresented: Bool { gesture.isPresented }
    var onError: ((Error) -> Void)?

    func pressMedia(_ session: CaptureSession, previewEnabled: Bool) {
        close(animated: false)
        mediaSession = session
        mediaGesture.press(at: ProcessInfo.processInfo.systemUptime)
        guard previewEnabled else { return }
        mediaHoldTask = Task { [weak self, weak session] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, let session, self.mediaGesture.hold(at: ProcessInfo.processInfo.systemUptime) else { return }
            self.gesture.present()
            self.schedulePresentation(session)
        }
    }

    func press(_ session: CaptureSession) {
        guard gesture.press(at: ProcessInfo.processInfo.systemUptime) else { close(); return }
        schedulePresentation(session)
    }

    func show(_ session: CaptureSession) {
        close(animated: false)
        gesture.present()
        schedulePresentation(session)
    }

    private func schedulePresentation(_ session: CaptureSession) {
        dismissing?.dispose()
        dismissing = nil
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
        let width = min(sourceSize.width, screen.width - 64, (screen.height - 64) * ratio)
        let size = CGSize(width: width, height: width / ratio)
        let rect = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                          width: size.width, height: size.height)
        let transition = PreviewPresentation(contentRect: rect)
        let view = transition.frameView
        presentation = transition
        transition.start()
        let capture = CapturePipeline(source: session.source)
        capture.output.mailbox.deliver = { [weak view] in view?.display($0) }
        capture.onError = { [weak self, weak transition] error in
            guard let self, self.presentation === transition else { return }
            self.close(animated: false)
            self.onError?(error)
        }
        capture.configure(viewport: .full, sourceSize: sourceSize, size: size, scale: transition.window.backingScaleFactor, fps: session.fps)
        capture.setRunning(true)
        pipeline = capture
        mouseGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
        mouseLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let insidePreview = event.window === self?.presentation?.window
            self?.close()
            return insidePreview ? nil : event
        }
    }

    func release() {
        if mediaGesture.pressedAt != nil {
            let target = mediaSession
            let toggle = mediaGesture.release(at: ProcessInfo.processInfo.systemUptime)
            close()
            if toggle { target?.mediaAction("toggle") }
            return
        }
        gesture.release(at: ProcessInfo.processInfo.systemUptime)
        if !gesture.isPresented { close() }
    }

    func close(animated: Bool = true) {
        mediaHoldTask?.cancel(); mediaHoldTask = nil
        mediaGesture.cancel(); mediaSession = nil
        generation += 1
        gesture.close()
        pipeline?.close(); pipeline = nil
        sourceID = nil
        session?.endInteraction(); session = nil
        if let mouseGlobal { NSEvent.removeMonitor(mouseGlobal); self.mouseGlobal = nil }
        if let mouseLocal { NSEvent.removeMonitor(mouseLocal); self.mouseLocal = nil }
        if let ending = presentation {
            presentation = nil
            dismissing?.dispose()
            dismissing = ending
            ending.dismiss(animated: animated) { [weak self, weak ending] in
                if self?.dismissing === ending { self?.dismissing = nil }
            }
        } else if !animated {
            dismissing?.dispose()
            dismissing = nil
        }
    }
}
#endif
