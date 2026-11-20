import Foundation

/// Bottom transport row in the panel's top-left coordinate system.
public struct MediaButtonLayout {
    public let play: CGRect
    public let previous: CGRect?
    public let next: CGRect?
    public let seek: CGRect?

    public init?(size: CGSize, seekable: Bool) {
        guard size.width >= 150, size.height >= 100 else { return nil }
        func fraction(_ compact: CGSize, _ large: CGSize) -> CGFloat {
            max(0, min(1, (size.width - compact.width) / (large.width - compact.width),
                       (size.height - compact.height) / (large.height - compact.height)))
        }
        let compact = CGSize(width: 240, height: 150)
        let standard = CGSize(width: 360, height: 200)
        let first = fraction(compact, standard)
        let second = fraction(standard, CGSize(width: 640, height: 360))
        let primary = 30 + 8 * first + 8 * second
        let secondary = 30 + 2 * first + 6 * second
        let gap = 8 + 2 * first + 2 * second
        seek = seekable && size.width >= 230 && size.height >= 145
            ? CGRect(x: 12, y: size.height - 43, width: size.width - 62, height: 36) : nil
        let bottom = seek.map { $0.minY - 7 } ?? (size.height - 10)
        play = CGRect(x: (size.width - primary) / 2, y: bottom - primary, width: primary, height: primary)
        if size.width >= 230 {
            let y = play.midY - secondary / 2
            previous = CGRect(x: play.minX - gap - secondary, y: y, width: secondary, height: secondary)
            next = CGRect(x: play.maxX + gap, y: y, width: secondary, height: secondary)
        } else {
            previous = nil
            next = nil
        }
    }
}
