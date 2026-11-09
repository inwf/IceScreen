#if os(macOS)
import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func orderOut(_ sender: Any?) {
        (contentView as? PanelSurface)?.cancelGesture()
        super.orderOut(sender)
    }
}
#endif
