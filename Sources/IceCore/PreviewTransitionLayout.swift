import Foundation

public struct PreviewTransitionLayout {
    /// AppKit screen coordinates, with the origin at the bottom left.
    public let thumbnail: CGRect
    /// Full preview image in thumbnail-local coordinates, before clipping.
    public let image: CGRect

    public static func overshoot(from source: CGPoint, to target: CGPoint) -> CGPoint {
        let dx = target.x - source.x, dy = target.y - source.y
        let fraction = min(0.035, 8 / max(1, hypot(dx, dy)))
        return CGPoint(x: target.x + dx * fraction, y: target.y + dy * fraction)
    }

    public init?(panel: CGRect, previewSize: CGSize, viewport: Viewport) {
        guard [panel.origin.x, panel.origin.y, panel.width, panel.height, previewSize.width, previewSize.height]
            .allSatisfy(\.isFinite), panel.width > 0, panel.height > 0, previewSize.width > 0, previewSize.height > 0 else { return nil }
        let crop = viewport.sourceRect(in: previewSize)
        let scale = min(panel.width / crop.width, panel.height / crop.height)
        let size = CGSize(width: crop.width * scale, height: crop.height * scale)
        thumbnail = CGRect(x: panel.midX - size.width / 2, y: panel.midY - size.height / 2,
                           width: size.width, height: size.height)
        image = CGRect(x: -crop.minX * scale, y: -(previewSize.height - crop.maxY) * scale,
                       width: previewSize.width * scale, height: previewSize.height * scale)
    }
}
