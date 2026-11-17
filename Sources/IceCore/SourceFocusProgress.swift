import Foundation

public struct SourceFocusProgress: Sendable {
    public struct Observation: Equatable, Codable, Sendable {
        public var foregroundPID: Int32?
        public var focusedWindowID: UInt32?
        public var onScreen: Bool
        public var onVisibleSpace: Bool
        public var hidden: Bool
        public var minimized: Bool?

        public init(foregroundPID: Int32?, focusedWindowID: UInt32?, onScreen: Bool,
                    onVisibleSpace: Bool, hidden: Bool, minimized: Bool?) {
            self.foregroundPID = foregroundPID
            self.focusedWindowID = focusedWindowID
            self.onScreen = onScreen
            self.onVisibleSpace = onVisibleSpace
            self.hidden = hidden
            self.minimized = minimized
        }
    }

    public enum Failure: Equatable, Sendable {
        case hidden, minimized, space, foreground, keyboardFocus, accessibility
    }

    public let processID: Int32
    public let windowID: UInt32
    private let deadline: TimeInterval
    private var nextAttempt: TimeInterval
    private var confirmedSince: TimeInterval?

    public init(processID: Int32, windowID: UInt32, startedAt: TimeInterval) {
        precondition(processID > 0 && windowID > 0 && startedAt.isFinite)
        self.processID = processID
        self.windowID = windowID
        deadline = startedAt + 5
        nextAttempt = startedAt
    }

    public func expired(at time: TimeInterval) -> Bool { time >= deadline }

    public mutating func beginAttempt(at time: TimeInterval) -> Bool {
        guard !expired(at: time), time >= nextAttempt else { return false }
        nextAttempt = time + 0.25
        return true
    }

    public mutating func pending() { confirmedSince = nil }

    public func requiresApplicationActivation(for value: Observation) -> Bool {
        value.hidden || value.foregroundPID != processID || !value.onVisibleSpace
    }

    public mutating func observe(_ value: Observation, at time: TimeInterval) -> Bool {
        guard !expired(at: time), failure(for: value) == nil else {
            confirmedSince = nil
            return false
        }
        if let confirmedSince { return time - confirmedSince >= 0.1 }
        confirmedSince = time
        return false
    }

    public func failure(for value: Observation) -> Failure? {
        if value.hidden { return .hidden }
        if value.minimized == true { return .minimized }
        if !value.onVisibleSpace { return .space }
        if value.foregroundPID != processID { return .foreground }
        if value.focusedWindowID == nil || value.minimized == nil { return .accessibility }
        if value.focusedWindowID != windowID { return .keyboardFocus }
        if !value.onScreen { return .accessibility }
        return nil
    }
}
