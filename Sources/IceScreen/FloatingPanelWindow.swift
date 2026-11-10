#if os(macOS)
import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if let surface = contentView as? PanelSurface, let owner = surface.owner {
            if event.type == .magnify {
                owner.magnify(with: event)
                return
            }
            if event.type == .endGesture { owner.endMagnification() }
        }
        super.sendEvent(event)
    }

    override func orderOut(_ sender: Any?) {
        (contentView as? PanelSurface)?.cancelGesture()
        super.orderOut(sender)
    }
}
#endif
