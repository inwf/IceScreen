import Foundation

public struct IdleDetector: Sendable {
    public var threshold: TimeInterval
    public var tolerance: Double
    public var sensitive = false
    public private(set) var didChange = false
    public private(set) var isInitialSample = false
    private var previous: [UInt8] = []
    private var lastChange: TimeInterval?

    public init(threshold: TimeInterval = 20, tolerance: Double = 2) {
        self.threshold = threshold
        self.tolerance = tolerance
    }

    public mutating func reset() { previous = []; lastChange = nil; didChange = false; isInitialSample = false }

    public mutating func observe(_ luminance: [UInt8], at time: TimeInterval) -> Bool {
        didChange = false
        isInitialSample = false
        guard !luminance.isEmpty else { return false }
        if lastChange == nil || previous.count != luminance.count {
            previous = luminance
            lastChange = time
            didChange = true
            isInitialSample = true
            return false
        }
        var sum = 0.0
        var largest = 0
        for (before, after) in zip(previous, luminance) {
            let difference = abs(Int(before) - Int(after))
            sum += Double(difference)
            largest = max(largest, difference)
        }
        didChange = sum / Double(luminance.count) > tolerance || (sensitive && largest >= 12)
        if didChange { previous = luminance; lastChange = time }
        return time - (lastChange ?? time) >= threshold
    }

    public func isIdle(at time: TimeInterval) -> Bool {
        guard let lastChange else { return false }
        return time - lastChange >= threshold
    }
}

public enum DetectionEvent: String, Sendable { case idle, change }

public struct ContentDetection: Sendable {
    private var lastActivity: TimeInterval?
    public private(set) var isIdle = false
    public init() {}
    public mutating func reset() { lastActivity = nil; isIdle = false }

    public mutating func activity(at time: TimeInterval, initial: Bool, changeAfter: TimeInterval) -> DetectionEvent? {
        let changed = !initial && lastActivity.map { time - $0 >= changeAfter } == true
        lastActivity = time
        isIdle = false
        return changed ? .change : nil
    }

    public mutating func tick(at time: TimeInterval, idleAfter: TimeInterval) -> DetectionEvent? {
        guard let lastActivity, time - lastActivity >= idleAfter, !isIdle else { return nil }
        isIdle = true
        return .idle
    }
}
