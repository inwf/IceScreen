#if os(macOS)
import AppKit
import QuartzCore
import IceCore

@MainActor
final class PreviewPresentation {
    let window: FloatingPanel
    let frameView: FrameView
    let clipView: NSView
    private let origin: PreviewTransitionLayout?
    private var dismissal: Task<Void, Never>?
    private var disposed = false
    private(set) var isRevealed = false

    init(contentRect: CGRect, origin: PreviewTransitionLayout?, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        self.origin = reduceMotion ? nil : origin
        let canvas = (self.origin.map { contentRect.union($0.thumbnail) } ?? contentRect).insetBy(dx: -24, dy: -24)
        window = FloatingPanel(contentRect: canvas, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.animationBehavior = .none
        let container = NSView(frame: CGRect(origin: .zero, size: window.frame.size))
        container.wantsLayer = true
        window.contentView = container
        clipView = NSView(frame: container.convert(window.convertFromScreen(contentRect), from: nil))
        clipView.wantsLayer = true
        clipView.layer?.masksToBounds = true
        clipView.layer?.cornerRadius = 16
        clipView.layer?.opacity = 0
        container.addSubview(clipView)
        frameView = FrameView(frame: CGRect(origin: .zero, size: contentRect.size))
        clipView.addSubview(frameView)
        frameView.onFirstFrameRendered = { [weak self] in self?.reveal() }
    }

    func start() {
        guard !disposed else { return }
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    // Animate only the presentation layers. AppKit and Metal keep the final view and drawable sizes throughout.
    private func transition(opening: Bool, duration: CFTimeInterval) {
        guard let clip = clipView.layer, let image = frameView.layer, let container = clipView.superview else { return }
        func animate(_ layer: CALayer, _ key: String, thumbnail: Any, full: Any, peak: Any? = nil) {
            let name = "preview." + key
            if opening, let peak {
                let path = CAKeyframeAnimation(keyPath: key)
                path.values = [thumbnail, peak, full]
                path.keyTimes = [0, 0.67, 1]
                path.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.22, 0.65, 0.36, 1),
                                        CAMediaTimingFunction(name: .easeInEaseOut)]
                path.duration = duration
                layer.add(path, forKey: name)
                return
            }
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = opening ? thumbnail : (layer.presentation()?.value(forKeyPath: key)
                ?? (layer.animation(forKey: name) as? CAKeyframeAnimation)?.values?.first
                ?? (layer.animation(forKey: name) as? CABasicAnimation)?.fromValue ?? full)
            animation.toValue = opening ? full : thumbnail
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: opening ? .easeOut : .easeInEaseOut)
            // Hold the last frame until disposal, without changing the model-layer geometry on close.
            if !opening { animation.fillMode = .forwards; animation.isRemovedOnCompletion = false }
            layer.add(animation, forKey: name)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if opening { clip.opacity = 1 }
        animate(clip, "opacity", thumbnail: Float(0), full: Float(1))
        if let origin {
            let rect = container.convertToLayer(container.convert(window.convertFromScreen(origin.thumbnail), from: nil))
            let anchor = clip.anchorPoint
            let position = CGPoint(x: rect.minX + rect.width * anchor.x, y: rect.minY + rect.height * anchor.y)
            let identity = NSValue(caTransform3D: CATransform3DIdentity)
            let peak = PreviewTransitionLayout.overshoot(from: position, to: clip.position)
            let zoom = 1 + min(0.018, 12 / max(1, clip.bounds.width, clip.bounds.height))
            animate(clip, "transform", thumbnail: identity, full: identity,
                    peak: NSValue(caTransform3D: CATransform3DMakeScale(zoom, zoom, 1)))
            animate(clip, "position", thumbnail: NSValue(point: position), full: NSValue(point: clip.position), peak: NSValue(point: peak))
            let fullSize = NSValue(size: clip.bounds.size)
            animate(clip, "bounds.size", thumbnail: NSValue(size: rect.size), full: fullSize, peak: fullSize)
            let scale = origin.image.width / image.bounds.width
            let offset = origin.image.origin
            let pivot = image.position
            let dy = clip.isGeometryFlipped ? rect.height - origin.image.maxY : offset.y
            var transform = CATransform3DMakeScale(scale, scale, 1)
            transform.m41 = offset.x + (scale - 1) * pivot.x
            transform.m42 = dy + (scale - 1) * pivot.y
            animate(image, "transform", thumbnail: NSValue(caTransform3D: transform), full: identity, peak: identity)
        }
        CATransaction.commit()
    }

    private func reveal() {
        guard !disposed, !isRevealed, dismissal == nil else { return }
        isRevealed = true
        window.hasShadow = true
        transition(opening: true, duration: origin == nil ? 0.14 : 0.30)
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        frameView.onFirstFrameRendered = nil
        window.ignoresMouseEvents = true
        guard animated, isRevealed, !disposed else {
            dispose()
            completion()
            return
        }
        transition(opening: false, duration: 0.16)
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            self?.dispose()
            completion()
        }
    }

    func dispose() {
        guard !disposed else { return }
        disposed = true
        dismissal?.cancel()
        dismissal = nil
        frameView.onFirstFrameRendered = nil
        clipView.layer?.removeAllAnimations()
        frameView.layer?.removeAllAnimations()
        frameView.releaseFrame()
        window.close()
    }
}
#endif
