import Foundation

/// 捏合增量在同一次手势内累加，并保持开始位置对应的来源内容不动。
public struct PinchZoomGesture {
    private var initial: Viewport?
    private var anchor = CGPoint(x: 0.5, y: 0.5)
    private var scale: Double = 1
    public var isActive: Bool { initial != nil }
    public init() {}

    public mutating func begin(viewport: Viewport, anchor: CGPoint) {
        initial = viewport
        self.anchor = CGPoint(x: anchor.x.isFinite ? min(1, max(0, anchor.x)) : 0.5,
                              y: anchor.y.isFinite ? min(1, max(0, anchor.y)) : 0.5)
        scale = 1
    }

    public mutating func change(by magnification: Double) -> Viewport? {
        guard let initial, magnification.isFinite else { return nil }
        let minimum = max(initial.rect.width, initial.rect.height)
        let maximum = min(initial.rect.width, initial.rect.height) * 32
        scale = min(maximum, max(minimum, scale + magnification))
        return initial.zoomed(by: scale, around: anchor)
    }

    public mutating func end() { initial = nil; scale = 1 }
}
