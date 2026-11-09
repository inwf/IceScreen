import Foundation

public struct MediaSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var pid: Int32
    public var bundleID: String
    public var parentBundleID: String?
    public var title: String
    public var duration: Double?
    public var elapsed: Double?
    public var timestamp: Double
    public var rate: Double
    public var canSeek: Bool
    public init(id: String, pid: Int32, bundleID: String, parentBundleID: String? = nil, title: String,
                duration: Double?, elapsed: Double?, timestamp: Double, rate: Double, canSeek: Bool) {
        self.id = id; self.pid = pid; self.bundleID = bundleID; self.parentBundleID = parentBundleID
        self.title = title; self.duration = duration; self.elapsed = elapsed; self.timestamp = timestamp
        self.rate = rate; self.canSeek = canSeek
    }
    public var playing: Bool { rate > 0 }
    public var seekable: Bool { canSeek && duration.map { $0.isFinite && $0 > 0 } == true && elapsed?.isFinite == true }
    public func position(at now: Double) -> Double {
        guard let elapsed, elapsed.isFinite, now.isFinite, timestamp.isFinite, rate.isFinite else { return 0 }
        let value = max(0, elapsed + max(0, now - timestamp) * max(0, rate))
        return min(value, duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? value)
    }
    public func seekPosition(relative seconds: Double, at now: Double) -> Double? {
        guard seekable, seconds.isFinite, let duration else { return nil }
        return min(duration, max(0, position(at: now) + seconds))
    }
    public static func match(_ values: [Self], pid: Int32, bundleID: String, title: String) -> Self? {
        let exact = values.filter { $0.pid == pid }
        let candidates = exact.isEmpty ? values.filter { $0.parentBundleID == bundleID || $0.bundleID == bundleID } : exact
        if candidates.count == 1 { return candidates[0] }
        let titled = candidates.filter { !$0.title.isEmpty && title.localizedCaseInsensitiveContains($0.title) }
        return titled.count == 1 ? titled[0] : nil
    }
}

public struct MediaRequest: Codable, Sendable {
    public var id: String?
    public var action: String
    public var position: Double?
    public init(id: String? = nil, action: String, position: Double? = nil) {
        self.id = id; self.action = action; self.position = position
    }
}
public struct MediaResponse: Codable, Sendable {
    public var snapshots: [MediaSnapshot]?
    public var error: String?
    public init(snapshots: [MediaSnapshot]? = nil, error: String? = nil) { self.snapshots = snapshots; self.error = error }
}

public struct MediaSpaceGesture: Sendable {
    public private(set) var pressedAt: TimeInterval?
    public private(set) var previewing = false
    public init() {}
    public mutating func press(at time: TimeInterval) { pressedAt = time; previewing = false }
    public mutating func hold(at time: TimeInterval) -> Bool {
        guard let pressedAt, time - pressedAt >= 0.25, !previewing else { return false }
        previewing = true; return true
    }
    public mutating func release(at time: TimeInterval) -> Bool {
        defer { cancel() }
        guard let pressedAt else { return false }
        return !previewing && time - pressedAt < 0.25
    }
    public mutating func cancel() { pressedAt = nil; previewing = false }
}
