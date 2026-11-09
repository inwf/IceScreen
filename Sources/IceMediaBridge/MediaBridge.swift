import Foundation
import IceCore
#if os(macOS)
import Darwin

private final class MediaBridge {
    typealias Clients = @convention(c) (DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
    typealias Info = @convention(c) (AnyObject, AnyObject?, Bool, DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    typealias Identifier = @convention(c) (AnyObject) -> Unmanaged<CFString>?
    typealias PID = @convention(c) (AnyObject) -> Int32
    typealias Origin = @convention(c) () -> AnyObject?
    typealias Send = @convention(c) (Int32, NSDictionary?, AnyObject?, AnyObject, Bool, DispatchQueue?, @escaping @convention(block) (AnyObject?) -> Void) -> Void
    private let handle: UnsafeMutableRawPointer
    private let clients: Clients
    private let info: Info
    private let pid: PID
    private let bundle: Identifier
    private let parent: Identifier
    private let origin: Origin
    private let send: Send
    private var targets: [String: AnyObject] = [:]
    private var refreshing = false
    private var refreshNumber = 0
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init() throws {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            throw BridgeError.unavailable
        }
        self.handle = handle
        func load<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else { throw BridgeError.unavailable }
            return unsafeBitCast(pointer, to: type)
        }
        clients = try load("MRMediaRemoteGetNowPlayingClients", Clients.self)
        info = try load("MRMediaRemoteGetNowPlayingInfoForClient", Info.self)
        pid = try load("MRNowPlayingClientGetProcessIdentifier", PID.self)
        bundle = try load("MRNowPlayingClientGetBundleIdentifier", Identifier.self)
        parent = try load("MRNowPlayingClientGetParentAppBundleIdentifier", Identifier.self)
        origin = try load("MRMediaRemoteGetLocalOrigin", Origin.self)
        send = try load("MRMediaRemoteSendCommandToClient", Send.self)
        let register = try load("MRMediaRemoteRegisterForNowPlayingNotifications", (@convention(c) (DispatchQueue) -> Void).self)
        register(.main)
        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification", "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"] {
            observers.append(NotificationCenter.default.addObserver(forName: .init(key(name)), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 0.4
    }

    private func key(_ name: String) -> String {
        guard let value = dlsym(handle, name)?.assumingMemoryBound(to: CFString?.self).pointee else { return name }
        return value as String
    }
    private func snapshot(_ client: AnyObject, info: NSDictionary, id: String) -> MediaSnapshot? {
        func value(_ suffix: String) -> Any? { info[key("kMRMediaRemoteNowPlayingInfo" + suffix)] }
        func number(_ suffix: String) -> Double? {
            guard let number = (value(suffix) as? NSNumber)?.doubleValue, number.isFinite else { return nil }
            return number
        }
        let title = value("Title") as? String ?? ""
        guard !title.isEmpty || number("Duration") != nil || number("PlaybackRate") != nil else { return nil }
        return MediaSnapshot(id: id, pid: pid(client), bundleID: bundle(client)?.takeUnretainedValue() as String? ?? "",
                             parentBundleID: parent(client)?.takeUnretainedValue() as String?, title: title,
                             duration: number("Duration"), elapsed: number("ElapsedTime"),
                             timestamp: (value("Timestamp") as? Date)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                             rate: number("PlaybackRate") ?? 0, canSeek: (value("ProhibitsSkip") as? Bool) != true)
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        refreshNumber += 1
        let number = refreshNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.refreshNumber == number, self.refreshing else { return }
            self.refreshNumber += 1; self.refreshing = false; self.targets.removeAll()
            Self.output(.init(error: "系统媒体服务没有响应。"))
        }
        clients(.main) { [weak self] list in
            guard let self, number == self.refreshNumber else { return }
            let group = DispatchGroup()
            var snapshots: [MediaSnapshot] = []
            var targets: [String: AnyObject] = [:]
            for client in (list as? [AnyObject] ?? []).prefix(32) {
                let identifier = "\(self.pid(client)):\(self.bundle(client)?.takeUnretainedValue() as String? ?? "")"
                group.enter()
                self.info(client, nil, false, .main) { data in
                    defer { group.leave() }
                    guard number == self.refreshNumber, let data, let value = self.snapshot(client, info: data, id: identifier) else { return }
                    targets[identifier] = client; snapshots.append(value)
                }
            }
            group.notify(queue: .main) {
                guard number == self.refreshNumber else { return }
                self.targets = targets; self.refreshing = false
                Self.output(.init(snapshots: snapshots))
            }
        }
    }

    func receive(_ request: MediaRequest) {
        if request.action == "refresh" { refresh(); return }
        guard let id = request.id, let target = targets[id] else {
            Self.output(.init(error: "来源媒体已结束，请等待播放状态更新。")); return
        }
        let codes: [String: Int32] = ["toggle": 2, "next": 4, "previous": 5, "seek": 24]
        guard let code = codes[request.action] else { return }
        var options: NSDictionary?
        if request.action == "seek" {
            guard let position = request.position, position.isFinite, position >= 0 else { return }
            options = [key("kMRMediaRemoteOptionPlaybackPosition"): position]
        }
        send(code, options, origin(), target, false, .main) { result in
            if let error = result as? NSError { Self.output(.init(error: error.localizedDescription)) }
            self.refresh()
        }
    }
    static func output(_ response: MediaResponse) {
        do {
            var data = try JSONEncoder().encode(response); data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch { exit(74) }
    }
    enum BridgeError: LocalizedError {
        case unavailable
        var errorDescription: String? { "当前系统的媒体控制接口不可用。" }
    }
}

// 通过系统解释器装载，兼容 macOS 15.4 及后续版本的媒体服务访问规则。
@_cdecl("IceScreenMediaMain")
public func IceScreenMediaMain() {
    do {
        let bridge = try MediaBridge()
        bridge.refresh()
        DispatchQueue.global(qos: .utility).async {
            while let line = readLine() {
                do {
                    let request = try JSONDecoder().decode(MediaRequest.self, from: Data(line.utf8))
                    DispatchQueue.main.async { bridge.receive(request) }
                } catch { MediaBridge.output(.init(error: "媒体控制请求格式错误。")); exit(65) }
            }
            exit(0)
        }
        withExtendedLifetime(bridge) { RunLoop.main.run() }
    } catch { MediaBridge.output(.init(error: error.localizedDescription)); exit(69) }
}
#endif
