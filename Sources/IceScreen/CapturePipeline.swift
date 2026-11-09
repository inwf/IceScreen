#if os(macOS)
import AppKit
import ScreenCaptureKit
import CoreImage
import Metal
import QuartzCore
import IceCore

final class FrameMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private var pending = false
    private var enabled = true
    var deliver: ((CVPixelBuffer) -> Void)?

    func submit(_ buffer: CVPixelBuffer) {
        lock.lock()
        guard enabled else { lock.unlock(); return }
        latest = buffer
        let schedule = !pending
        pending = true
        lock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.drain() } }
    }

    private func drain() {
        lock.lock()
        let buffer = latest
        latest = nil
        pending = false
        lock.unlock()
        if let buffer { deliver?(buffer) }
    }

    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        if !value { latest = nil }
        lock.unlock()
    }
}

final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let mailbox = FrameMailbox()
    let queue = DispatchQueue(label: "org.icescreen.frames", qos: .userInteractive)
    var onActivity: ((Bool) -> Void)?
    var onFailure: ((SCStream, Error) -> Void)?
    private var detectIdle = false
    private var lastFrame: CVPixelBuffer?
    private var running = false
    private var lastSample: TimeInterval = 0
    private var detector = IdleDetector(threshold: 0.5)

    func configureIdle(_ enabled: Bool, sensitive: Bool = false) {
        queue.async { [self] in
            detectIdle = enabled
            detector.sensitive = sensitive
            detector.reset()
            lastSample = 0
            if enabled, running, let lastFrame { sample(lastFrame, at: ProcessInfo.processInfo.systemUptime) }
        }
    }

    func setRunning(_ value: Bool) {
        queue.async { [self] in running = value; detector.reset(); lastSample = 0; lastFrame = nil }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.onFailure?(stream, error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard running, type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        acceptFrame(buffer)
    }

    // 由帧队列调用；保留一个缓冲区以便在静止画面上开启检测时建立基准。
    func acceptFrame(_ buffer: CVPixelBuffer) {
        guard running else { return }
        mailbox.submit(buffer)
        lastFrame = buffer
        let now = ProcessInfo.processInfo.systemUptime
        guard detectIdle, now - lastSample >= 1 else { return }
        sample(buffer, at: now)
    }

    private func sample(_ buffer: CVPixelBuffer, at now: TimeInterval) {
        lastSample = now
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var values: [UInt8] = []
        let side = detector.sensitive ? 64 : 32
        values.reserveCapacity(side * side)
        for y in 0..<side {
            for x in 0..<side {
                let offset = min(height - 1, (2 * y + 1) * height / (2 * side)) * stride
                    + min(width - 1, (2 * x + 1) * width / (2 * side)) * 4
                values.append(UInt8((Int(bytes[offset]) + Int(bytes[offset + 1]) * 2 + Int(bytes[offset + 2])) / 4))
            }
        }
        _ = detector.observe(values, at: now)
        if detector.didChange {
            let initial = detector.isInitialSample
            DispatchQueue.main.async { [weak self] in self?.onActivity?(initial) }
        }
    }
}

@MainActor
final class CapturePipeline {
    let source: SCWindow
    let output = StreamOutput()
    private let filter: SCContentFilter
    private var stream: SCStream?
    private var running = false
    private var desiredRunning = false
    private var revision = 0
    private var desiredConfig: SCStreamConfiguration?
    private var worker: Task<Void, Never>?
    private var disposed = false
    private var appliedRevision = -1
    private var lastConfiguration: ConfigurationKey?
    var onError: ((Error) -> Void)?

    private struct ConfigurationKey: Equatable {
        let viewport: Viewport
        let sourceSize: CGSize
        let pixels: CGSize
        let fps: Int
    }

    init(source: SCWindow) {
        self.source = source
        self.filter = SCContentFilter(desktopIndependentWindow: source)
        output.onFailure = { [weak self] stoppedStream, error in
            guard let self, !self.disposed, self.stream === stoppedStream else { return }
            self.running = false
            self.desiredRunning = false
            self.stream = nil
            self.appliedRevision = -1
            self.output.setRunning(false)
            self.output.mailbox.setEnabled(false)
            self.onError?(error)
        }
    }

    func configure(viewport: Viewport, sourceSize: CGSize, size: CGSize, scale: Double, fps: Int) {
        guard !disposed else { return }
        let pixels = CaptureSizing.pixels(points: size, scale: scale)
        let key = ConfigurationKey(viewport: viewport, sourceSize: sourceSize, pixels: pixels, fps: fps)
        guard lastConfiguration != key else { return }
        lastConfiguration = key
        let config = SCStreamConfiguration()
        config.width = Int(pixels.width)
        config.height = Int(pixels.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true
        config.sourceRect = viewport == .full ? .zero : viewport.sourceRect(in: sourceSize)
        desiredConfig = config
        revision += 1
        reconcile()
    }

    func setRunning(_ value: Bool) {
        guard !disposed else { return }
        guard desiredRunning != value else { return }
        desiredRunning = value
        output.setRunning(value)
        output.mailbox.setEnabled(value)
        reconcile()
    }

    func close() {
        disposed = true
        desiredRunning = false
        output.setRunning(false)
        output.mailbox.setEnabled(false)
        output.mailbox.deliver = nil
        output.onActivity = nil
        reconcile()
    }

    private func reconcile() {
        guard worker == nil else { return }
        worker = Task { [self] in
            defer { worker = nil }
            do {
                while true {
                    if !desiredRunning {
                        if running, let stream {
                            try await stream.stopCapture()
                            running = false
                        }
                        stream = nil
                        appliedRevision = -1
                        if !desiredRunning { break }
                    }
                    guard let config = desiredConfig else { break }
                    let currentRevision = revision
                    if stream == nil {
                        let newStream = SCStream(filter: filter, configuration: config, delegate: output)
                        try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                        stream = newStream
                        appliedRevision = currentRevision
                    } else if appliedRevision != currentRevision {
                        try await stream?.updateConfiguration(config)
                        appliedRevision = currentRevision
                    }
                    if !running, desiredRunning {
                        if let starting = stream {
                            try await starting.startCapture()
                            running = stream === starting
                        }
                    }
                    if desiredRunning == running, appliedRevision == revision { break }
                }
            } catch {
                desiredRunning = false
                output.setRunning(false)
                output.mailbox.setEnabled(false)
                let failedStream = stream
                stream = nil
                appliedRevision = -1
                if running, let failedStream {
                    do { try await failedStream.stopCapture() }
                    catch { if !disposed { onError?(error) } }
                }
                running = false
                if !disposed { onError?(error) }
            }
        }
    }
}

@MainActor
private final class FrameRenderer {
    static let shared = FrameRenderer()
    let device: MTLDevice
    let commands: MTLCommandQueue
    let context: CIContext
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    private init() {
        guard let gpu = MTLCreateSystemDefaultDevice(), let queue = gpu.makeCommandQueue() else {
            fatalError("IceScreen requires a Metal-capable Mac.")
        }
        device = gpu
        commands = queue
        context = CIContext(mtlDevice: gpu, options: [.cacheIntermediates: false])
    }
}

@MainActor
final class FrameView: NSView {
    private let metalLayer = CAMetalLayer()
    private let renderer = FrameRenderer.shared
    private var current: CVPixelBuffer?
    private let inFlight = DispatchSemaphore(value: 2)
    private var frameGeneration = 0
    var onFirstFrameRendered: (() -> Void)?
    var enhanced = false { didSet { if oldValue != enhanced { render() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.maximumDrawableCount = 2
        metalLayer.isOpaque = true
        layer = metalLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() { super.layout(); updateSize(); render() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); updateSize(); render() }

    private func updateSize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(2, bounds.width * scale), height: max(2, bounds.height * scale))
    }

    func display(_ buffer: CVPixelBuffer) { current = buffer; render() }
    func redraw() { render() }
    func releaseFrame() { frameGeneration += 1; current = nil }

    private func render() {
        guard let current, window?.isVisible == true, window?.alphaValue ?? 0 > 0,
              bounds.width > 0, bounds.height > 0,
              inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = metalLayer.nextDrawable(), let command = renderer.commands.makeCommandBuffer() else {
            inFlight.signal(); return
        }
        var image = CIImage(cvPixelBuffer: current)
        if enhanced {
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.2])
                .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.65])
        }
        let target = metalLayer.drawableSize
        image = image.transformed(by: CGAffineTransform(scaleX: target.width / image.extent.width,
                                                        y: target.height / image.extent.height))
        renderer.context.render(image, to: drawable.texture, commandBuffer: command,
                                bounds: CGRect(origin: .zero, size: target), colorSpace: renderer.colorSpace)
        let semaphore = inFlight
        if onFirstFrameRendered != nil {
            let generation = frameGeneration
            command.addCompletedHandler { [weak self] command in
                semaphore.signal()
                guard command.status == .completed else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.frameGeneration == generation else { return }
                    let callback = self.onFirstFrameRendered
                    self.onFirstFrameRendered = nil
                    callback?()
                }
            }
        } else {
            command.addCompletedHandler { _ in semaphore.signal() }
        }
        command.present(drawable)
        command.commit()
    }
}
#endif
