import Foundation

public enum SourcePlacement {
    public static func parkedFrame(_ frame: CGRect, screens: [CGRect]) -> CGRect? {
        guard let left = screens.map(\.minX).min(), !screens.isEmpty, frame.width > 0, frame.height > 0 else { return nil }
        // 横向移出所有屏幕，保留纵向位置，避免 macOS 将标题栏重新约束到桌面。
        return CGRect(x: left - frame.width - 8, y: frame.minY, width: frame.width, height: frame.height)
    }
    public static func restoredFrame(_ original: CGRect, screens: [CGRect]) -> CGRect {
        let desktop = screens.reduce(CGRect.null) { $0.union($1) }
        if desktop.contains(original), visibleArea(original, screens: screens) > 0 { return original }
        guard let screen = screens.max(by: { intersectionArea(original, $0) < intersectionArea(original, $1) }) else { return original }
        let width = min(original.width, screen.width), height = min(original.height, screen.height)
        return CGRect(x: min(max(original.minX, screen.minX), screen.maxX - width),
                      y: min(max(original.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
    public static func isParked(_ frame: CGRect, at expected: CGRect) -> Bool {
        abs(frame.minX - expected.minX) < 32 && abs(frame.minY - expected.minY) < 32
    }
    public static func visibleArea(_ frame: CGRect, screens: [CGRect]) -> Double {
        screens.reduce(0) { $0 + intersectionArea(frame, $1) }
    }
    private static func intersectionArea(_ a: CGRect, _ b: CGRect) -> Double {
        let result = a.intersection(b)
        return result.isNull ? 0 : result.width * result.height
    }
}

public enum StageManagerGeometry {
    public static func isThumbnailShape(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard frame.width > 0, frame.height > 0, frame.width <= 320, frame.height <= 240 else { return false }
        return screens.contains { screen in
            let nearEdge = frame.midX <= screen.minX + 180 || frame.midX >= screen.maxX - 180
            return nearEdge && frame.maxY > screen.minY && frame.minY < screen.maxY
                && frame.maxX >= screen.minX - 40 && frame.minX <= screen.maxX + 40
        }
    }
    public static func isInactive(enabled: Bool, frame: CGRect, fullSize: CGSize, screens: [CGRect], intentionallyParked: Bool) -> Bool {
        enabled && !intentionallyParked && frame.width < fullSize.width * 0.7 && frame.height < fullSize.height * 0.7
            && isThumbnailShape(frame, screens: screens)
    }
}
