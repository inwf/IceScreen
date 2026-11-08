import Foundation

public struct IdleDetector: Sendable {
    public var threshold: TimeInterval
    public var tolerance: Double
    private var previous: [UInt8] = []
    private var lastChange: TimeInterval?

    public init(threshold: TimeInterval = 20, tolerance: Double = 2) {
        self.threshold = threshold
        self.tolerance = tolerance
    }

    public mutating func reset() { previous = []; lastChange = nil }

    public mutating func observe(_ luminance: [UInt8], at time: TimeInterval) -> Bool {
        guard !luminance.isEmpty else { return false }
        if lastChange == nil || previous.count != luminance.count {
            previous = luminance
            lastChange = time
            return false
        }
        let difference = zip(previous, luminance).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) }
            / Double(luminance.count)
        if difference > tolerance { previous = luminance; lastChange = time }
        return time - (lastChange ?? time) >= threshold
    }

    public func isIdle(at time: TimeInterval) -> Bool {
        guard let lastChange else { return false }
        return time - lastChange >= threshold
    }
}
