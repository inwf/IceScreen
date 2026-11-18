#if os(macOS)
import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // The custom handle overlaps AppKit's borderless-window resize area.
        // Let the handle track its own gesture, including movement outside the panel.
        if event.type == .leftMouseDown, event.window === self, isVisible, !ignoresMouseEvents,
           let surface = contentView as? PanelSurface,
           let handle = surface.target(atWindowPoint: event.locationInWindow) as? PanelResizeHandle {
            handle.mouseDown(with: event)
            return
        }
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
