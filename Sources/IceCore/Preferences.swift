import Foundation

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var function: Bool
    public var label: String

    public init(keyCode: UInt16 = 49, command: Bool = false, option: Bool = true,
                control: Bool = true, function: Bool = false, label: String = "Space") {
        self.keyCode = keyCode; self.command = command; self.option = option
        self.control = control; self.function = function; self.label = label
    }

    public var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (command ? "⌘" : "") + (function ? "fn " : "") + label
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public static let frameRates = [1, 5, 10, 15, 24, 30, 60]
    public var multiWindow = true
    public var defaultFPS = 15
    public var appFrameRates: [String: Int] = [:]
    public var preferredWidth: Double = 360
    public var autoHide = false
    public var enhanceContrast = false
    public var idleDetection = false
    public var idleSeconds: Double = 20
    public var shortcut = Shortcut()

    public init() {}

    public func fps(for bundleID: String) -> Int {
        let value = appFrameRates[bundleID] ?? defaultFPS
        return Self.frameRates.contains(value) ? value : 15
    }

    public mutating func normalize() {
        if !Self.frameRates.contains(defaultFPS) { defaultFPS = 15 }
        appFrameRates = appFrameRates.filter { Self.frameRates.contains($0.value) }
        preferredWidth = preferredWidth.isFinite ? min(1600, max(160, preferredWidth)) : 360
        idleSeconds = idleSeconds.isFinite ? min(600, max(5, idleSeconds)) : 20
    }
}
