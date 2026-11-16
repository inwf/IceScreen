import AppKit
import ApplicationServices
import IceCore

@MainActor
enum NativeFocusDiagnostics {
    private static var output: FileHandle?
    private static var phase = "startup"
    private static var applications: [String: NSRunningApplication] = [:]
    private static weak var session: CaptureSession?
    static var captureFailure: String? { session?.failure ?? session?.surface.frameView.renderFailure }

    static func configure(at url: URL) throws {
        precondition(FileManager.default.createFile(atPath: url.path, contents: nil))
        output = try FileHandle(forWritingTo: url)
    }

    static func track(_ name: String, application: NSRunningApplication) {
        applications[name] = application
        snapshot("application_ready")
    }

    static func track(_ value: CaptureSession) {
        session = value
        snapshot("capture_session_ready")
    }

    static func begin(_ name: String) {
        phase = name
        snapshot("begin")
    }

    static func snapshot(_ event: String, file: StaticString = #file, line: UInt = #line) {
        var record: [String: Any] = [
            "time": ISO8601DateFormatter().string(from: Date()), "phase": phase,
            "event": event, "file": String(describing: file), "line": line,
            "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0,
            "frontmostBundle": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        ]
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        record["applications"] = applications.map { name, application -> [String: Any] in
            let root = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.05)
            var focused: CFTypeRef?, listed: CFTypeRef?
            let focusedStatus = AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &focused)
            let listStatus = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &listed)
            var state: [String: Any] = [
                "label": name, "pid": application.processIdentifier,
                "terminated": application.isTerminated, "hidden": application.isHidden, "active": application.isActive,
                "axFocusedStatus": focusedStatus.rawValue, "axWindowsStatus": listStatus.rawValue
            ]
            if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                state["focusedWindow"] = describe(unsafeBitCast(focused, to: AXUIElement.self))
            }
            state["axWindows"] = (listed as? [AXUIElement] ?? []).map(describe)
            state["serverWindows"] = windows.filter { $0[kCGWindowOwnerPID as String] as? pid_t == application.processIdentifier }
                .map { entry -> [String: Any] in
                    var window: [String: Any] = [
                        "id": entry[kCGWindowNumber as String] as? CGWindowID ?? 0,
                        "title": entry[kCGWindowName as String] as? String ?? "",
                        "onScreen": entry[kCGWindowIsOnscreen as String] as? Bool == true,
                        "bounds": entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
                    ]
                    if let id = entry[kCGWindowNumber as String] as? CGWindowID {
                        do { window["spaces"] = try WindowActivation.spaceIDs(for: id) }
                        catch { window["spaceError"] = error.localizedDescription }
                    }
                    return window
                }
            return state
        }
        do { record["visibleSpaces"] = try WindowActivation.visibleSpaceIDs() }
        catch { record["spaceError"] = error.localizedDescription }
        if let session {
            record["panel"] = [
                "window": session.panel.windowNumber, "visible": session.panel.isVisible,
                "onActiveSpace": session.panel.isOnActiveSpace, "key": session.panel.isKeyWindow,
                "frame": NSStringFromRect(session.panel.frame), "sourceWindow": session.source.windowID,
                "status": session.status, "capturedFrame": session.hasCapturedFrame,
                "renderer": session.surface.frameView.renderingState
            ]
        }
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([0x0a])
        try! output?.write(contentsOf: data)
        try! FileHandle.standardOutput.write(contentsOf: data)
    }

    private static func describe(_ element: AXUIElement) -> [String: Any] {
        AXUIElementSetMessagingTimeout(element, 0.05)
        var result: [String: Any] = [:]
        do { result["id"] = try WindowActivation.windowID(of: element) ?? 0 }
        catch { result["idError"] = error.localizedDescription }
        for attribute in [kAXTitleAttribute, kAXRoleAttribute, kAXMainAttribute, kAXMinimizedAttribute, "AXFullScreen"] {
            var value: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            result[attribute + "Status"] = status.rawValue
            if let value = value as? String { result[attribute] = value }
            else if let value = value as? NSNumber { result[attribute] = value }
        }
        return result
    }
}
