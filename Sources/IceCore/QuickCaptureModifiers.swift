import Foundation

public struct QuickCaptureModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
    public static let all: Self = [.command, .option, .control, .shift, .function]

    public init(command: Bool, option: Bool, control: Bool, shift: Bool, function: Bool) {
        self = []
        if command { insert(.command) }; if option { insert(.option) }; if control { insert(.control) }
        if shift { insert(.shift) }; if function { insert(.function) }
    }

    public init(trigger: TriggerModifier) {
        switch trigger {
        case .command: self = .command
        case .option: self = .option
        case .control: self = .control
        case .shift: self = .shift
        case .function: self = .function
        }
    }

    public var isValid: Bool { !isEmpty && subtracting(.all).isEmpty }
    public var display: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
        + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        + (contains(.function) ? "fn" : "")
    }

    public func matches(_ held: Self) -> Bool { isValid && self == held }
}

public struct ModifierChordRecording {
    public private(set) var candidate: QuickCaptureModifiers = []
    private var rejected = false
    public init() {}

    public mutating func update(_ held: QuickCaptureModifiers) -> QuickCaptureModifiers? {
        if rejected {
            if held.isEmpty { reset() }
            return nil
        }
        if held.isEmpty {
            defer { reset() }
            return candidate.isValid ? candidate : nil
        }
        candidate.formUnion(held)
        return nil
    }
    public mutating func rejectUntilRelease() { candidate = []; rejected = true }
    public mutating func reset() { candidate = []; rejected = false }
}
