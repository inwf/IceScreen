#if os(macOS)
import AppKit

/// 全局捏合按开始位置绑定浮窗，避免非激活面板把手势留给后台应用。
@MainActor
final class PanelMagnificationRouter {
    var sessions: () -> [CaptureSession] = { [] }
    private weak var target: CaptureSession?
    private var tracking = false
    private var claimed = false
    private var delivered = false
    private var origin = NSPoint.zero

    @discardableResult
    func handle(_ event: NSEvent, at point: NSPoint) -> Bool {
        switch event.type {
        case .beginGesture:
            reset()
            begin(at: point)
            return false
        case .endGesture:
            reset()
            return false
        case .magnify:
            if event.phase.contains(.began) && delivered { reset() }
            if !tracking { begin(at: point) }
            let consumed = claimed
            if claimed, let target {
                let first = !delivered
                let origin = origin
                let amount = Double(event.magnification)
                let finished = !event.phase.intersection([.ended, .cancelled]).isEmpty
                let cancelled = event.phase.contains(.cancelled)
                // 捕获流更新离开事件 tap 回调，保持系统输入处理及时返回。
                DispatchQueue.main.async { [weak target] in
                    guard let target else { return }
                    if first { target.beginMagnification(at: origin) }
                    if !cancelled { target.changeMagnification(by: amount) }
                    if finished { target.endMagnification() }
                }
                delivered = true
            }
            if !event.phase.intersection([.ended, .cancelled]).isEmpty { reset() }
            return consumed
        default: return false
        }
    }

    private func begin(at point: NSPoint) {
        let candidates = sessions().filter { !$0.hidden && !$0.autoHidden && !$0.stageInactive }
        let panel = PanelHitTesting.frontmost(at: point, among: candidates.map(\.panel))
        target = candidates.first { $0.panel === panel }
        origin = point
        tracking = true
        claimed = target != nil
        delivered = false
    }

    func reset() {
        if delivered, let target {
            DispatchQueue.main.async { [weak target] in target?.endMagnification() }
        }
        target = nil
        tracking = false
        claimed = false
        delivered = false
    }
}
#endif
