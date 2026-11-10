#if os(macOS)
import AppKit

enum MenuBarIcon {
    @MainActor static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            let scoop = NSBezierPath()
            scoop.move(to: NSPoint(x: 4, y: 9))
            scoop.curve(to: NSPoint(x: 4.5, y: 5), controlPoint1: NSPoint(x: 1.8, y: 8), controlPoint2: NSPoint(x: 2.6, y: 5))
            scoop.curve(to: NSPoint(x: 13.5, y: 5), controlPoint1: NSPoint(x: 4, y: 0.4), controlPoint2: NSPoint(x: 14, y: 0.4))
            scoop.curve(to: NSPoint(x: 14, y: 9), controlPoint1: NSPoint(x: 15.4, y: 5), controlPoint2: NSPoint(x: 16.2, y: 8))
            scoop.close()
            scoop.lineWidth = 1.3
            scoop.lineJoinStyle = .round
            scoop.stroke()

            let cone = NSBezierPath()
            cone.move(to: NSPoint(x: 4.6, y: 9))
            cone.line(to: NSPoint(x: 9, y: 16.5))
            cone.line(to: NSPoint(x: 13.4, y: 9))
            cone.move(to: NSPoint(x: 6.4, y: 12))
            cone.line(to: NSPoint(x: 11.6, y: 12))
            cone.lineWidth = 1.3
            cone.lineJoinStyle = .round
            cone.lineCapStyle = .round
            cone.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "IceScreen"
        return image
    }
}
#endif
