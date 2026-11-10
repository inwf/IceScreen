import Foundation

public enum SourcePlacement {
    public static func parkedFrame(_ frame: CGRect, screens: [CGRect]) -> CGRect? {
        parkingDestinations(frame, screens: screens).first
    }
    public static func parkingDestinations(_ frame: CGRect, screens: [CGRect]) -> [CGRect] {
        guard valid(frame) else { return [] }
        let displays = screens.filter(valid).sorted {
            let lhs = intersectionArea(frame, $0), rhs = intersectionArea(frame, $1)
            if lhs != rhs { return lhs > rhs }
            return hypot(frame.midX - $0.midX, frame.midY - $0.midY) < hypot(frame.midX - $1.midX, frame.midY - $1.midY)
        }
        var result: [CGRect] = []
        for screen in displays {
            // 优先同时越过水平和下方边界，让标题栏也离开显示区域。
            let origins = [CGPoint(x: screen.maxX + 10, y: screen.maxY + 10),
                           CGPoint(x: screen.minX - frame.width - 10, y: screen.maxY + 10),
                           CGPoint(x: max(screen.minX, min(frame.minX, screen.maxX - frame.width)), y: screen.maxY + 10)]
            for origin in origins {
                let destination = CGRect(origin: origin, size: frame.size)
                if valid(destination), visibleArea(destination, screens: displays) == 0, !result.contains(destination) {
                    result.append(destination)
                }
            }
        }
        return result
    }
    public static func isOutsideDisplays(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard valid(frame), !screens.isEmpty, screens.allSatisfy(valid) else { return false }
        return screens.allSatisfy {
            let overlap = frame.intersection($0)
            return overlap.isNull || overlap.width <= 2 || overlap.height <= 2
        }
    }
    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty
            && [frame.minX, frame.minY, frame.width, frame.height, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
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
