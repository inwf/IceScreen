#if os(macOS)
import AppKit
import ApplicationServices
import IceCore

private struct WindowRecoveryRecord: Decodable {
    var id: CGWindowID
    var pid: pid_t
    var launchedAt: Date
    var original: CGRect
    var parked: CGRect
    var moving: Bool?
}

@MainActor
enum SourceWindowRecovery {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IceScreen/WindowRecovery", isDirectory: true)
    }
    static var screens: [CGRect] {
        let height = CGDisplayBounds(CGMainDisplayID()).height
        return NSScreen.screens.map { CGRect(x: $0.frame.minX, y: height - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
    }

    static func watch(_ path: String) {
        _ = FileHandle.standardInput.readDataToEndOfFile()
        let url = URL(fileURLWithPath: path)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSApplication.shared.setActivationPolicy(.prohibited)
        recover(url)
    }

    // 启动时处理已保存的恢复记录；捕获会话不创建位置记录。
    static func recoverAbandoned() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            let journals = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for url in journals where url.pathExtension == "json" { recover(url) }
        } catch { fputs("IceScreen recovery: \(error.localizedDescription)\n", stderr) }
    }
    private static func recover(_ url: URL) {
        do {
            let records = try JSONDecoder().decode([WindowRecoveryRecord].self, from: Data(contentsOf: url))
            var failed = false
            for record in records {
                do { try restore(record) }
                catch { failed = true; fputs("IceScreen: \(error.localizedDescription)\n", stderr) }
            }
            if !failed { try FileManager.default.removeItem(at: url) }
        } catch { fputs("IceScreen recovery: \(error.localizedDescription)\n", stderr) }
    }

    private static func restore(_ record: WindowRecoveryRecord) throws {
        guard let app = NSRunningApplication(processIdentifier: record.pid), app.launchDate == record.launchedAt,
              !app.isTerminated else { return }
        let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, record.id) as? [[String: Any]] ?? []
        guard entries.contains(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == record.id }) else { return }
        let target = try element(pid: record.pid, id: record.id)
        let current = try frame(target)
        guard record.moving == true || SourcePlacement.isParked(current, at: record.parked)
                || SourcePlacement.visibleArea(current, screens: screens) == 0 else { return }
        let destination = SourcePlacement.restoredFrame(record.original, screens: screens)
        if destination.size != current.size {
            var size = destination.size
            let status = AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
            guard status == .success else { throw RequestError.message("恢复来源窗口尺寸失败（\(status.rawValue)）。") }
        }
        var point = destination.origin
        let status = AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &point)!)
        guard status == .success else { throw RequestError.message("恢复来源窗口位置失败（\(status.rawValue)）。") }
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
}
#endif
