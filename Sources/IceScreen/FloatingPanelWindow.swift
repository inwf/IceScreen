#if os(macOS)
import AppKit

final class FloatingPanel: NSPanel {
    private weak var contentMouseTarget: PanelInput?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // 内容手势由非激活浮窗持有，保持按下、拖动、抬起的接收对象一致。
        switch event.type {
        case .leftMouseDown:
            if let surface = contentView as? PanelSurface,
               (!styleMask.contains(.resizable) || surface.bounds.insetBy(dx: 4, dy: 4)
                    .contains(surface.convert(event.locationInWindow, from: nil))),
               let input = surface.target(atWindowPoint: event.locationInWindow) as? PanelInput {
                contentMouseTarget = input
                input.mouseDown(with: event)
                return
            }
        case .leftMouseDragged:
            if let input = contentMouseTarget {
                input.mouseDragged(with: event)
                return
            }
        case .leftMouseUp:
            if let input = contentMouseTarget {
                contentMouseTarget = nil
                input.mouseUp(with: event)
                return
            }
        default: break
        }
        super.sendEvent(event)
    }

    override func orderOut(_ sender: Any?) {
        contentMouseTarget?.cancelGesture()
        contentMouseTarget = nil
        super.orderOut(sender)
    }
}
#endif
