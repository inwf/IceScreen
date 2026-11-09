import Foundation

public struct CaptureCandidate: Sendable {
    public let rect: CGRect
    public let semantic: Bool
    public init(rect: CGRect, semantic: Bool = false) { self.rect = rect; self.semantic = semantic }
}

public enum SmartCapture {
    public static func select(at point: CGPoint, candidates: [CaptureCandidate]) -> Viewport {
        if let rect = detected(at: point, candidates: candidates) { return Viewport(rect: rect) }
        return Viewport(rect: CGRect(x: point.x - 0.125, y: point.y - 0.125, width: 0.25, height: 0.25))
    }
    public static func detected(at point: CGPoint, candidates: [CaptureCandidate]) -> CGRect? {
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let valid = candidates.filter {
            let r = $0.rect
            return [r.minX, r.minY, r.width, r.height].allSatisfy(\.isFinite)
                && r.width >= 0.06 && r.height >= 0.06 && r.width * r.height < 0.94
                && unit.insetBy(dx: -0.01, dy: -0.01).contains(r) && r.contains(point)
        }
        // 语义区域优先；同类选取外层边界，避免只截取视频内部的矩形。
        let ordered = valid.sorted {
            if $0.semantic != $1.semantic { return $0.semantic }
            return $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height
        }
        return ordered.first?.rect.intersection(unit)
    }

    public static func fromVision(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}
