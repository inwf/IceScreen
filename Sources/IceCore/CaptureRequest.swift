import Foundation

public struct CaptureRequest: Codable, Equatable, Sendable {
    public var app: String?
    public var window: String?
    public var anchor: ZoomAnchor = .center
    public var zoom: Double = 1
    public var region = false

    public init(app: String? = nil, window: String? = nil) {
        self.app = app
        self.window = window
    }

    public static func parse(_ arguments: [String]) throws -> CaptureRequest {
        var result = CaptureRequest()
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            if key == "--region" { result.region = true; index += 1; continue }
            guard ["--app", "--window", "--zoom"].contains(key) else {
                throw RequestError.message("Unknown argument: \(key)")
            }
            index += 1
            guard index < arguments.count, !arguments[index].hasPrefix("--"), !arguments[index].isEmpty else {
                throw RequestError.message("Missing value for \(key)")
            }
            let value = arguments[index]
            switch key {
            case "--app": result.app = value
            case "--window": result.window = value
            default:
                let parts = value.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 2, let anchor = ZoomAnchor(rawValue: String(parts[0])),
                      let zoom = Double(parts[1].hasSuffix("x") ? parts[1].dropLast() : parts[1][...]),
                      zoom.isFinite, (1...32).contains(zoom) else {
                    throw RequestError.message("Zoom must be position:factor (1...32), for example bottom-right:4x")
                }
                result.anchor = anchor
                result.zoom = zoom
            }
            index += 1
        }
        return result
    }

    public func matches(appName: String, bundleID: String, title: String, windowID: UInt32) -> Bool {
        let appMatches = app.map {
            appName.localizedCaseInsensitiveContains($0) || bundleID.caseInsensitiveCompare($0) == .orderedSame
        } ?? true
        let windowMatches = window.map {
            if let id = UInt32($0) { return id == windowID }
            return title.localizedCaseInsensitiveContains($0)
        } ?? true
        return appMatches && windowMatches
    }

    public static let usage = """
    IceScreen — floating window monitor for macOS 14+
    Usage: IceScreen [--app NAME] [--window TITLE_OR_ID] [--zoom POSITION:FACTOR] [--region]
           IceScreen --help

    Positions: top-left, top, top-right, left, center, right, bottom-left, bottom, bottom-right
    Example: IceScreen --app Terminal --zoom bottom-left:3x
    Without arguments, opens the control center. Requests are forwarded to the running instance.
    """
}

public enum RequestError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
