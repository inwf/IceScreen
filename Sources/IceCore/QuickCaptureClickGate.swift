import Foundation

/// 在双击判定期间保留原始点击；普通点击和拖动按原顺序交回系统。
public struct QuickCaptureClickGate<Event> {
    public enum Input { case down, up, dragged, moved, interrupt }
    public struct Decision {
        public var consume = false
        public var replay: [Event] = []
        public var capture = false
    }

    public let interval: TimeInterval
    public let movementTolerance: Double
    public private(set) var deadline: TimeInterval?
    private var pending: [Event] = []
    private var origin = CGPoint.zero
    private var firstReleased = false
    private var capturing = false

    public init(interval: TimeInterval, movementTolerance: Double = 4) {
        precondition(interval > 0 && interval.isFinite && movementTolerance > 0)
        self.interval = interval
        self.movementTolerance = movementTolerance
    }

    public mutating func handle(_ input: Input, event: @autoclosure () -> Event, at time: TimeInterval,
                                position: CGPoint, eligible: Bool, clickCount: Int = 1) -> Decision {
        var result = Decision()
        result.replay = expire(at: time)
        if capturing {
            switch input {
            case .up: capturing = false; result.consume = true
            case .down, .dragged: result.consume = true
            case .moved, .interrupt: break
            }
            return result
        }
        let moved = hypot(position.x - origin.x, position.y - origin.y) > movementTolerance
        switch input {
        case .down:
            if !pending.isEmpty, firstReleased, eligible, (1...2).contains(clickCount), !moved {
                pending.removeAll(keepingCapacity: true)
                deadline = nil
                firstReleased = false
                capturing = true
                result.consume = true
                result.capture = true
            } else {
                result.replay += flush()
                if eligible, clickCount == 1 {
                    origin = position
                    pending = [event()]
                    deadline = time + interval
                    result.consume = true
                }
            }
        case .up:
            if !pending.isEmpty, !firstReleased {
                if eligible && !moved {
                    pending.append(event())
                    firstReleased = true
                    result.consume = true
                } else { result.replay += flush() }
            }
        case .dragged:
            if !pending.isEmpty {
                if moved || !eligible { result.replay += flush() }
                else { result.consume = true }
            }
        case .moved:
            if moved { result.replay += flush() }
        case .interrupt:
            result.replay += flush()
        }
        return result
    }

    public mutating func expire(at time: TimeInterval) -> [Event] {
        guard let deadline, time >= deadline else { return [] }
        return flush()
    }

    /// 设置切换时释放尚未识别的点击；已经识别的双击仍需吞掉第二次抬起。
    public mutating func flush() -> [Event] {
        let events = pending
        pending.removeAll(keepingCapacity: true)
        deadline = nil
        firstReleased = false
        return events
    }

    public mutating func reset() -> [Event] {
        capturing = false
        return flush()
    }
}
