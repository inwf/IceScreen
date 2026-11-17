import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public var name: String {
        switch self {
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }
}

public enum L10n {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var language: AppLanguage = .chinese
    }
    private static let state = State()

    public static var language: AppLanguage {
        get {
            state.lock.lock()
            defer { state.lock.unlock() }
            return state.language
        }
        set {
            state.lock.lock()
            defer { state.lock.unlock() }
            state.language = newValue
        }
    }

    public static func text(_ chinese: String, _ english: String, language: AppLanguage? = nil) -> String {
        switch language ?? self.language {
        case .chinese: return chinese
        case .english: return english
        }
    }
}
