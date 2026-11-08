import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum ZoomAnchor: String, CaseIterable, Codable, Sendable {
    case topLeft = "top-left", top, topRight = "top-right"
    case left, center, right
    case bottomLeft = "bottom-left", bottom, bottomRight = "bottom-right"

    public var point: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .left: return CGPoint(x: 0, y: 0.5)
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .right: return CGPoint(x: 1, y: 0.5)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        }
    }
}

/// 使用左上角原点、0...1 范围描述来源窗口中的捕获区域。
public struct Viewport: Equatable, Sendable {
    public static let full = Viewport(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
    public private(set) var rect: CGRect

    public init(rect: CGRect) {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite) else {
            self.rect = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }
        let r = rect.standardized
        let w = min(1, max(1.0 / 32, r.width))
        let h = min(1, max(1.0 / 32, r.height))
        self.rect = CGRect(x: min(1 - w, max(0, r.minX)),
                           y: min(1 - h, max(0, r.minY)), width: w, height: h)
    }

    public var magnification: Double { 1 / Double(max(rect.width, rect.height)) }

    public func zoomed(by factor: Double, around anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> Viewport {
        guard factor.isFinite, factor > 0 else { return self }
        let ax = min(1, max(0, anchor.x)), ay = min(1, max(0, anchor.y))
        let width = min(1, max(1.0 / 32, rect.width / factor))
        let height = min(1, max(1.0 / 32, rect.height / factor))
        return Viewport(rect: CGRect(x: rect.minX + (rect.width - width) * ax,
                                     y: rect.minY + (rect.height - height) * ay,
                                     width: width, height: height))
    }

    public func panned(x: Double, y: Double) -> Viewport {
        Viewport(rect: rect.offsetBy(dx: x * rect.width, dy: y * rect.height))
    }

    public func selecting(_ selection: CGRect) -> Viewport {
        let bounded = selection.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !bounded.isNull, bounded.width > 0, bounded.height > 0 else { return self }
        return Viewport(rect: CGRect(x: rect.minX + bounded.minX * rect.width,
                                     y: rect.minY + bounded.minY * rect.height,
                                     width: bounded.width * rect.width,
                                     height: bounded.height * rect.height))
    }

    public func sourceRect(in size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
               width: rect.width * size.width, height: rect.height * size.height)
    }

    public static func initial(anchor: ZoomAnchor, factor: Double) -> Viewport {
        full.zoomed(by: factor, around: anchor.point)
    }
}

public enum CaptureSizing {
    public static func pixels(points: CGSize, scale: Double, maxDimension: Double = 4096) -> CGSize {
        let w = max(2, points.width * scale), h = max(2, points.height * scale)
        let ratio = min(1, maxDimension / max(w, h))
        return CGSize(width: max(2, (w * ratio / 2).rounded(.up) * 2),
                      height: max(2, (h * ratio / 2).rounded(.up) * 2))
    }
}
