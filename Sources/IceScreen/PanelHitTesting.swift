#if os(macOS)
import AppKit

@MainActor
enum PanelHitTesting {
    static func frontmost(at point: NSPoint, among panels: [NSPanel]) -> NSPanel? {
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        return panels.first {
            $0.windowNumber == number && $0.isVisible && $0.isOnActiveSpace && !$0.ignoresMouseEvents
        }
    }
}
#endif
