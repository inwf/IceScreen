#if os(macOS)
import AppKit
import QuartzCore

@MainActor
final class PreviewPresentation {
    let window: FloatingPanel
    let frameView: FrameView
    private let reduceMotion: Bool
    private var dismissal: Task<Void, Never>?
    private var disposed = false
    private(set) var isRevealed = false

    init(contentRect: CGRect, reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        self.reduceMotion = reduceMotion
        let padding: CGFloat = 24
        window = FloatingPanel(contentRect: contentRect.insetBy(dx: -padding, dy: -padding),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
        frameView = FrameView(frame: CGRect(origin: CGPoint(x: padding, y: padding), size: contentRect.size))
        frameView.layer?.cornerRadius = 16
        frameView.layer?.masksToBounds = true
        frameView.layer?.opacity = 0
        container.addSubview(frameView)
        window.contentView = container
        frameView.onFirstFrameRendered = { [weak self] in self?.reveal() }
    }

    func start() {
        guard !disposed else { return }
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func reveal() {
        guard !disposed, !isRevealed, dismissal == nil, let layer = frameView.layer else { return }
        isRevealed = true
        window.hasShadow = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        opacity.duration = 0.16
        layer.add(opacity, forKey: "preview.opacity")
        if !reduceMotion {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.mass = 1
            spring.stiffness = 300
            spring.damping = 20
            spring.initialVelocity = 0
            spring.fromValue = NSValue(caTransform3D: transform(scale: 0.94, offsetY: -12))
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "preview.spring")
        }
    }

    func dismiss(animated: Bool, completion: @escaping () -> Void) {
        frameView.onFirstFrameRendered = nil
        window.ignoresMouseEvents = true
        guard animated, isRevealed, !disposed, let layer = frameView.layer else {
            dispose()
            completion()
            return
        }
        let current = layer.presentation() ?? layer
        let currentTransform = current.transform
        let currentOpacity = current.opacity
        let endTransform = reduceMotion ? CATransform3DIdentity : transform(scale: 0.98, offsetY: 0)
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = endTransform
        CATransaction.commit()

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = currentOpacity
        opacity.toValue = 0
        opacity.duration = 0.14
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: currentTransform)
        scale.toValue = NSValue(caTransform3D: endTransform)
        scale.duration = 0.14
        let group = CAAnimationGroup()
        group.animations = reduceMotion ? [opacity] : [opacity, scale]
        group.duration = 0.14
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(group, forKey: "preview.dismiss")
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
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
        frameView.layer?.removeAllAnimations()
        frameView.releaseFrame()
        window.close()
    }

    private func transform(scale: CGFloat, offsetY: CGFloat) -> CATransform3D {
        guard let layer = frameView.layer else { return CATransform3DIdentity }
        let pivot = CGPoint(x: layer.bounds.width * (0.5 - layer.anchorPoint.x),
                            y: layer.bounds.height * (0.5 - layer.anchorPoint.y))
        var value = CATransform3DMakeTranslation(pivot.x, pivot.y + offsetY, 0)
        value = CATransform3DScale(value, scale, scale, 1)
        return CATransform3DTranslate(value, -pivot.x, -pivot.y, 0)
    }
}
#endif
