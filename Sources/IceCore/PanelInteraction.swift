import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct FunctionKeyGesture: Sendable {
    private var pressedAt: TimeInterval?
    private var used = false

    public init() {}

    public mutating func flagsChanged(function: Bool, otherModifiers: Bool, at time: TimeInterval) -> Bool {
        if function {
            if pressedAt == nil { pressedAt = time; used = otherModifiers }
            else if otherModifiers { used = true }
            return false
        }
        defer { reset() }
        guard let pressedAt else { return false }
        return !used && !otherModifiers && (0...0.45).contains(time - pressedAt)
    }

    public mutating func consume() { if pressedAt != nil { used = true } }
    public mutating func reset() { pressedAt = nil; used = false }
}

public struct ModifierTapSequence: Sendable {
    public var interval: TimeInterval
    public private(set) var deadline: TimeInterval?
    public init(interval: TimeInterval = 0.3) { self.interval = interval }

    /// 第二次轻按返回 true；首次轻按等待单击期限结束。
    public mutating func tap(at time: TimeInterval) -> Bool {
        if let deadline, time <= deadline { self.deadline = nil; return true }
        deadline = time + interval
        return false
    }
    public mutating func takeSingle(at time: TimeInterval) -> Bool {
        guard let deadline, time >= deadline else { return false }
        self.deadline = nil
        return true
    }
    public mutating func reset() { deadline = nil }
}

public enum HoverAction: Equatable, Sendable {
    case frameRate, idleDetection, zoomIn, zoomOut, close

    public static func resolve(keyCode: UInt16, repeated: Bool) -> HoverAction? {
        switch keyCode {
        case 3: return repeated ? nil : .frameRate
        case 2: return repeated ? nil : .idleDetection
        case 24, 69: return .zoomIn
        case 27, 78: return .zoomOut
        case 51, 117: return repeated ? nil : .close
        default: return nil
        }
    }
}

public struct PanelVisibility: Equatable, Sendable {
    public private(set) var manuallyHidden = false
    public private(set) var automaticallyHidden = false
    public private(set) var closeDeadline: TimeInterval?
    public var paused = false
    public var systemSleeping = false
    public var displaySleeping = false
    public var interacting = false

    public init() {}
    public var shouldCapture: Bool {
        !manuallyHidden && !automaticallyHidden && !paused && !systemSleeping && !displaySleeping
    }

    public mutating func toggleManual(at time: TimeInterval) {
        manuallyHidden.toggle()
        automaticallyHidden = false
        closeDeadline = manuallyHidden ? time + 60 : nil
    }

    public mutating func updatePointer(inside: Bool, autoHide: Bool) {
        automaticallyHidden = !manuallyHidden && !interacting && autoHide && inside
    }

    public func isExpired(at time: TimeInterval) -> Bool {
        closeDeadline.map { time >= $0 } ?? false
    }
}

public enum PanelGeometry {
    public static func fittedFrame(_ frame: CGRect, aspectRatio: Double, visibleFrame: CGRect) -> CGRect {
        guard aspectRatio.isFinite, aspectRatio > 0, visibleFrame.width > 0, visibleFrame.height > 0 else { return frame }
        let width = min(max(80, frame.width), visibleFrame.width, visibleFrame.height * aspectRatio)
        let height = width / aspectRatio
        return CGRect(x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
                      y: min(max(frame.maxY - height, visibleFrame.minY), visibleFrame.maxY - height),
                      width: width, height: height)
    }
}
