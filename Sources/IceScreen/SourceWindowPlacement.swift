#if os(macOS)
import AppKit
import ApplicationServices
import ScreenCaptureKit
import IceCore

struct WindowPlacementRecord: Codable {
    var id: CGWindowID
    var pid: pid_t
    var launchedAt: Date
    var original: CGRect
    var parked: CGRect
}

@MainActor
final class SourceWindowPlacement {
    private var records: [CGWindowID: WindowPlacementRecord] = [:]
    private var watcher: Process?
    private var lifetime: FileHandle?
    private let journal: URL
    var onError: ((String) -> Void)?
    var onParked: ((CGWindowID, Bool) -> Void)?

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IceScreen/WindowRecovery", isDirectory: true)
    }
    static var screens: [CGRect] {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        return NSScreen.screens.map { CGRect(x: $0.frame.minX, y: height - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
    }
    init() { journal = Self.directory.appendingPathComponent(UUID().uuidString + ".json") }
    func isParked(_ id: CGWindowID) -> Bool { records[id] != nil }

    func park(_ source: SCWindow) throws {
        guard records[source.windowID] == nil, let pid = source.owningApplication?.processID,
              let app = NSRunningApplication(processIdentifier: pid), let launchedAt = app.launchDate else { return }
        guard AXIsProcessTrusted() else { throw RequestError.message("移走来源窗口需要辅助功能权限。") }
        let target = try Self.element(pid: pid, id: source.windowID)
        var full: CFTypeRef?, minimized: CFTypeRef?
        AXUIElementCopyAttributeValue(target, "AXFullScreen" as CFString, &full)
        AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &minimized)
        guard full as? Bool != true, minimized as? Bool != true else {
            throw RequestError.message("全屏或已最小化的来源窗口保持原位。")
        }
        var movable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(target, kAXPositionAttribute as CFString, &movable) == .success, movable.boolValue else {
            throw RequestError.message("来源应用不允许移动这个窗口。")
        }
        let original = try Self.frame(target)
        guard let destination = SourcePlacement.parkedFrame(original, screens: Self.screens) else { return }
        try ensureWatcher()
        records[source.windowID] = .init(id: source.windowID, pid: pid, launchedAt: launchedAt, original: original, parked: destination)
        try persist()
        do {
            try Self.position(target, destination.origin)
            let actual = try Self.frame(target)
            guard SourcePlacement.visibleArea(actual, screens: Self.screens) <= max(actual.height, actual.width) * 4 else {
                throw RequestError.message("来源应用限制了窗口位置，已保留在屏幕内。")
            }
            records[source.windowID]?.parked = actual
            try persist()
            onParked?(source.windowID, true)
        } catch {
            try restore(source.windowID, force: true)
            throw error
        }
    }

    func restore(_ id: CGWindowID, force: Bool = false) throws {
        guard let record = records[id] else { return }
        try Self.restoreRecord(record, force: force)
        records[id] = nil
        try persist()
        onParked?(id, false)
    }

    func refresh() {
        for record in Array(records.values) {
            do {
                guard let app = NSRunningApplication(processIdentifier: record.pid), app.launchDate == record.launchedAt else {
                    records[record.id] = nil; try persist(); onParked?(record.id, false); continue
                }
                guard let entry = (CGWindowListCopyWindowInfo(.optionIncludingWindow, record.id) as? [[String: Any]])?.first,
                      let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
                // 用户已经自行移动窗口时，尊重当前位置并取消恢复记录。
                if !SourcePlacement.isParked(frame, at: record.parked), SourcePlacement.visibleArea(frame, screens: Self.screens) > 100 {
                    records[record.id] = nil; try persist(); onParked?(record.id, false)
                }
            } catch { onError?(error.localizedDescription) }
        }
    }
    func restoreAll() {
        for id in Array(records.keys) {
            do { try restore(id) } catch { onError?(error.localizedDescription) }
        }
    }
    func shutdown() {
        restoreAll()
        lifetime?.closeFile(); lifetime = nil
        // 管道 EOF 让恢复进程处理仍未恢复的记录后退出。
        watcher = nil
    }
    private func ensureWatcher() throws {
        if watcher?.isRunning == true { return }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard let executable = Bundle.main.executableURL else { throw RequestError.message("找不到窗口恢复程序。") }
        let process = Process(), pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--watch-source-windows", journal.path]
        process.standardInput = pipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        try process.run()
        watcher = process; lifetime = pipe.fileHandleForWriting
    }
    private func persist() throws {
        if records.isEmpty {
            if FileManager.default.fileExists(atPath: journal.path) { try FileManager.default.removeItem(at: journal) }
        } else {
            try JSONEncoder().encode(Array(records.values)).write(to: journal, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        }
    }
    static func watch(_ path: String) {
        // 只在父进程关闭管道或结束时恢复，无轮询计时器。
        _ = FileHandle.standardInput.readDataToEndOfFile()
        let url = URL(fileURLWithPath: path)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSApplication.shared.setActivationPolicy(.prohibited)
        recover(url)
    }

    static func recoverAbandoned() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let journals = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for url in journals where url.pathExtension == "json" { recover(url) }
        } catch { fputs("IceScreen recovery: \(error.localizedDescription)\n", stderr) }
    }
    private static func recover(_ url: URL) {
        do {
            let records = try JSONDecoder().decode([WindowPlacementRecord].self, from: Data(contentsOf: url))
            var failed = false
            for record in records {
                do { try restoreRecord(record, force: false) }
                catch { failed = true; fputs("IceScreen: \(error.localizedDescription)\n", stderr) }
            }
            if !failed { try FileManager.default.removeItem(at: url) }
        } catch { fputs("IceScreen recovery: \(error.localizedDescription)\n", stderr) }
    }

    private static func restoreRecord(_ record: WindowPlacementRecord, force: Bool) throws {
        guard let app = NSRunningApplication(processIdentifier: record.pid), app.launchDate == record.launchedAt,
              !app.isTerminated else { return }
        let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, record.id) as? [[String: Any]] ?? []
        guard entries.contains(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == record.id }) else { return }
        let target = try element(pid: record.pid, id: record.id)
        let current = try frame(target)
        guard force || SourcePlacement.isParked(current, at: record.parked)
                || SourcePlacement.visibleArea(current, screens: screens) == 0 else { return }
        let destination = SourcePlacement.restoredFrame(record.original, screens: screens)
        if destination.size != current.size {
            var size = destination.size
            let status = AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
            guard status == .success else { throw RequestError.message("恢复来源窗口尺寸失败（\(status.rawValue)）。") }
        }
        try position(target, destination.origin)
    }
    static func element(pid: pid_t, id: CGWindowID) throws -> AXUIElement {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let target = try windows.first(where: { try WindowActivation.windowID(of: $0) == id }) else {
            throw RequestError.message("找不到来源窗口的辅助功能对象。")
        }
        AXUIElementSetMessagingTimeout(target, 0.15)
        return target
    }
    static func frame(_ target: AXUIElement) throws -> CGRect {
        var p: CFTypeRef?, s: CFTypeRef?, point = CGPoint.zero, size = CGSize.zero
        guard AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(target, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID(),
              AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else {
            throw RequestError.message("无法读取来源窗口位置。")
        }
        return CGRect(origin: point, size: size)
    }
    private static func position(_ target: AXUIElement, _ point: CGPoint) throws {
        var point = point
        let status = AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
        guard status == .success else { throw RequestError.message("移动来源窗口失败（\(status.rawValue)）。") }
    }
}
#endif
