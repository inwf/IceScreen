import Foundation

public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var function: Bool
    public var shift: Bool
    public var label: String

    public init(keyCode: UInt16 = 35, command: Bool = false, option: Bool = false,
                control: Bool = false, function: Bool = true, shift: Bool = false, label: String = "P") {
        self.keyCode = keyCode; self.command = command; self.option = option
        self.control = control; self.function = function; self.label = label
        self.shift = shift
    }

    public var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + (function ? "fn " : "") + label
    }

    public var regionVariant: Shortcut? {
        var result = self
        if !shift { result.shift = true }
        else if !option { result.option = true }
        else if !control { result.control = true }
        else if !command { result.command = true }
        else if !function { result.function = true }
        else { return nil }
        return result
    }

    public func matches(keyCode: UInt16, command: Bool, option: Bool, control: Bool, function: Bool, shift: Bool) -> Bool {
        self.keyCode == keyCode && self.command == command && self.option == option && self.control == control
            && self.function == function && self.shift == shift
    }

    public func usesSameKeys(as other: Shortcut) -> Bool {
        matches(keyCode: other.keyCode, command: other.command, option: other.option,
                control: other.control, function: other.function, shift: other.shift)
    }

    private enum CodingKeys: String, CodingKey { case keyCode, command, option, control, function, shift, label }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        command = try container.decode(Bool.self, forKey: .command)
        option = try container.decode(Bool.self, forKey: .option)
        control = try container.decode(Bool.self, forKey: .control)
        function = try container.decode(Bool.self, forKey: .function)
        shift = try container.decodeIfPresent(Bool.self, forKey: .shift) ?? false
        label = try container.decode(String.self, forKey: .label)
    }
}

public enum SourceFocusBehavior: String, CaseIterable, Codable, Sendable {
    case keep, pause, close
}

public enum TriggerModifier: String, CaseIterable, Codable, Sendable {
    case function, shift, control, option, command
    public var display: String {
        switch self {
        case .function: return "fn"; case .shift: return "⇧"; case .control: return "⌃"
        case .option: return "⌥"; case .command: return "⌘"
        }
    }
}

public enum ShortcutAction: Sendable { case capture, region, closeAll }

public struct Preferences: Codable, Equatable, Sendable {
    public static let frameRates = [1, 5, 10, 15, 24, 30, 60]
    public var multiWindow = false
    public var defaultFPS = 10
    public var appFrameRates: [String: Int] = [:]
    public var preferredWidth: Double = 360
    public var autoHide = false
    public var enhanceContrast = false
    public var idleDetection = false
    public var idleSeconds: Double = 20
    public var changeDetection = false
    public var changeSeconds: Double = 10
    public var sensitiveDetection = false
    public var detectionNotifications = true
    public var detectionCommand = ""
    public var detectionCommandTimeout: Double = 15
    public var shortcut = Shortcut()
    public var regionShortcut: Shortcut?
    public var closeAllShortcut: Shortcut?
    public var clickToFocus = true
    public var sourceFocusBehavior: SourceFocusBehavior = .keep
    public var showOnFullscreenSpaces = true
    public var quickRegionCapture = true
    public var cornerRadius: Double = 14
    public var showHoverHints = true
    public var panelPosition: ZoomAnchor = .bottomRight
    public var triggerModifier: TriggerModifier = .function
    public var quickLook = true
    public var dimOnHover = true
    public var hoverBlur: Double = 0.35
    public var panelOpacity: Double = 1
    public var showMenuBarIcon = true

    public var effectiveRegionShortcut: Shortcut? { regionShortcut ?? shortcut.regionVariant }

    public init() {}

    public func shortcutConflict(_ candidate: Shortcut, for action: ShortcutAction) -> String? {
        var proposed = self
        switch action {
        case .capture: proposed.shortcut = candidate
        case .region: proposed.regionShortcut = candidate
        case .closeAll: proposed.closeAllShortcut = candidate
        }
        if let region = proposed.effectiveRegionShortcut, proposed.shortcut.usesSameKeys(as: region) {
            return "窗口捕获与区域捕获需要使用不同的快捷键。"
        }
        if let close = proposed.closeAllShortcut,
           proposed.shortcut.usesSameKeys(as: close) || proposed.effectiveRegionShortcut?.usesSameKeys(as: close) == true {
            return "关闭全部浮窗的快捷键与捕获快捷键冲突。"
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case multiWindow, defaultFPS, appFrameRates, preferredWidth, autoHide, enhanceContrast, idleDetection, idleSeconds, shortcut
        case regionShortcut, closeAllShortcut, clickToFocus, sourceFocusBehavior, showOnFullscreenSpaces
        case quickRegionCapture, cornerRadius, showHoverHints, panelPosition, triggerModifier, quickLook
        case changeDetection, changeSeconds, sensitiveDetection, detectionNotifications, detectionCommand, detectionCommandTimeout
        case dimOnHover, hoverBlur, panelOpacity, showMenuBarIcon
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        multiWindow = try c.decodeIfPresent(Bool.self, forKey: .multiWindow) ?? multiWindow
        defaultFPS = try c.decodeIfPresent(Int.self, forKey: .defaultFPS) ?? defaultFPS
        appFrameRates = try c.decodeIfPresent([String: Int].self, forKey: .appFrameRates) ?? appFrameRates
        preferredWidth = try c.decodeIfPresent(Double.self, forKey: .preferredWidth) ?? preferredWidth
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? autoHide
        enhanceContrast = try c.decodeIfPresent(Bool.self, forKey: .enhanceContrast) ?? enhanceContrast
        idleDetection = try c.decodeIfPresent(Bool.self, forKey: .idleDetection) ?? idleDetection
        idleSeconds = try c.decodeIfPresent(Double.self, forKey: .idleSeconds) ?? idleSeconds
        changeDetection = try c.decodeIfPresent(Bool.self, forKey: .changeDetection) ?? changeDetection
        changeSeconds = try c.decodeIfPresent(Double.self, forKey: .changeSeconds) ?? changeSeconds
        sensitiveDetection = try c.decodeIfPresent(Bool.self, forKey: .sensitiveDetection) ?? sensitiveDetection
        detectionNotifications = try c.decodeIfPresent(Bool.self, forKey: .detectionNotifications) ?? detectionNotifications
        detectionCommand = try c.decodeIfPresent(String.self, forKey: .detectionCommand) ?? detectionCommand
        detectionCommandTimeout = try c.decodeIfPresent(Double.self, forKey: .detectionCommandTimeout) ?? detectionCommandTimeout
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? shortcut
        regionShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .regionShortcut)
        closeAllShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .closeAllShortcut)
        clickToFocus = try c.decodeIfPresent(Bool.self, forKey: .clickToFocus) ?? clickToFocus
        sourceFocusBehavior = try c.decodeIfPresent(SourceFocusBehavior.self, forKey: .sourceFocusBehavior) ?? sourceFocusBehavior
        showOnFullscreenSpaces = try c.decodeIfPresent(Bool.self, forKey: .showOnFullscreenSpaces) ?? showOnFullscreenSpaces
        quickRegionCapture = try c.decodeIfPresent(Bool.self, forKey: .quickRegionCapture) ?? quickRegionCapture
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        showHoverHints = try c.decodeIfPresent(Bool.self, forKey: .showHoverHints) ?? showHoverHints
        panelPosition = try c.decodeIfPresent(ZoomAnchor.self, forKey: .panelPosition) ?? panelPosition
        triggerModifier = try c.decodeIfPresent(TriggerModifier.self, forKey: .triggerModifier) ?? triggerModifier
        quickLook = try c.decodeIfPresent(Bool.self, forKey: .quickLook) ?? quickLook
        dimOnHover = try c.decodeIfPresent(Bool.self, forKey: .dimOnHover) ?? dimOnHover
        hoverBlur = try c.decodeIfPresent(Double.self, forKey: .hoverBlur) ?? hoverBlur
        panelOpacity = try c.decodeIfPresent(Double.self, forKey: .panelOpacity) ?? panelOpacity
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? showMenuBarIcon
    }

    public func fps(for bundleID: String) -> Int {
        let value = appFrameRates[bundleID] ?? defaultFPS
        return Self.frameRates.contains(value) ? value : 10
    }

    public mutating func normalize() {
        if !Self.frameRates.contains(defaultFPS) { defaultFPS = 10 }
        appFrameRates = appFrameRates.filter { Self.frameRates.contains($0.value) }
        preferredWidth = preferredWidth.isFinite ? min(1600, max(160, preferredWidth)) : 360
        idleSeconds = idleSeconds.isFinite ? min(600, max(5, idleSeconds)) : 20
        changeSeconds = changeSeconds.isFinite ? min(600, max(1, changeSeconds)) : 10
        detectionCommandTimeout = detectionCommandTimeout.isFinite ? min(300, max(1, detectionCommandTimeout)) : 15
        hoverBlur = hoverBlur.isFinite ? min(1, max(0, hoverBlur)) : 0.35
        panelOpacity = panelOpacity.isFinite ? min(1, max(0.35, panelOpacity)) : 1
        cornerRadius = cornerRadius.isFinite ? min(30, max(0, cornerRadius)) : 14
    }
}
