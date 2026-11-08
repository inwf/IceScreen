#if os(macOS)
import AppKit
import ScreenCaptureKit
import ApplicationServices
import IceCore

@MainActor
final class WindowCatalog: ObservableObject {
    @Published private(set) var windows: [SCWindow] = []
    @Published private(set) var loading = false
    @Published var error: String?
    private var refreshTask: Task<Void, Never>?

    func refresh() async {
        if let refreshTask { await refreshTask.value; return }
        let task = Task { await loadWindows() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func loadWindows() async {
        loading = true
        defer { loading = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            windows = content.windows.filter {
                $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
                    && $0.owningApplication != nil && $0.windowLayer == 0
                    && $0.frame.width >= 48 && $0.frame.height >= 48
            }.sorted {
                let lhs = $0.owningApplication?.applicationName ?? ""
                let rhs = $1.owningApplication?.applicationName ?? ""
                return lhs == rhs ? ($0.title ?? "") < ($1.title ?? "") : lhs < rhs
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func resolve(_ request: CaptureRequest, preferredPID: pid_t?) throws -> SCWindow {
        let candidates = windows.filter {
            request.matches(appName: $0.owningApplication?.applicationName ?? "",
                            bundleID: $0.owningApplication?.bundleIdentifier ?? "",
                            title: $0.title ?? "", windowID: $0.windowID)
        }
        if request.app == nil, request.window == nil, let preferredPID {
            let focused = candidates.filter { $0.owningApplication?.processID == preferredPID }
            if let match = focusedWindow(in: focused, pid: preferredPID) { return match }
            if let visible = focused.first(where: \.isOnScreen) { return visible }
            throw RequestError.message("当前应用没有可捕获的窗口，请先聚焦需要捕获的窗口。")
        }
        guard !candidates.isEmpty else { throw RequestError.message("找不到匹配窗口，请确认应用已打开窗口。") }
        if candidates.count > 1, request.window != nil {
            throw RequestError.message("有多个匹配窗口，请使用 --app 或数字窗口 ID 指定窗口。")
        }
        if let pid = candidates.first?.owningApplication?.processID,
           let focused = focusedWindow(in: candidates, pid: pid) { return focused }
        return candidates.first(where: \.isOnScreen) ?? candidates[0]
    }

    private func focusedWindow(in candidates: [SCWindow], pid: pid_t) -> SCWindow? {
        let app = AXUIElementCreateApplication(pid)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(result, to: AXUIElement.self)
        return candidates.min { matchScore(element, $0) < matchScore(element, $1) }
    }

    func window(at point: CGPoint) -> SCWindow? {
        let order = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for entry in order {
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  let window = windows.first(where: { $0.windowID == id }), window.frame.contains(point) else { continue }
            return window
        }
        return nil
    }

    func focus(_ source: SCWindow) throws {
        guard let owner = source.owningApplication,
              let app = NSRunningApplication(processIdentifier: owner.processID) else {
            throw RequestError.message("来源应用已经退出。")
        }
        let root = AXUIElementCreateApplication(owner.processID)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &result) == .success,
              let windows = result as? [AXUIElement], !windows.isEmpty else {
            app.activate(options: [])
            throw RequestError.message("需要辅助功能权限才能定位来源窗口。")
        }
        let currentInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, source.windowID) as? [[String: Any]]
        let bounds = currentInfo?.first?[kCGWindowBounds as String] as? [String: Any]
        let currentFrame = bounds.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? source.frame
        let target = windows.min { matchScore($0, source, frame: currentFrame) < matchScore($1, source, frame: currentFrame) }!
        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        app.activate(options: [])
        let status = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        if status != .success { throw RequestError.message("无法聚焦来源窗口（\(status.rawValue)）。") }
    }

    private func matchScore(_ element: AXUIElement, _ window: SCWindow, frame: CGRect? = nil) -> Double {
        var titleValue: CFTypeRef?, positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        var position = CGPoint.zero, size = CGSize.zero
        if let value = positionValue, CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &position)
        }
        if let value = sizeValue, CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size)
        }
        let titlePenalty: Double = (titleValue as? String) == window.title ? 0 : 100_000
        let target = frame ?? window.frame
        return titlePenalty + abs(position.x - target.minX) + abs(position.y - target.minY)
            + abs(size.width - target.width) + abs(size.height - target.height)
    }
}
#endif
