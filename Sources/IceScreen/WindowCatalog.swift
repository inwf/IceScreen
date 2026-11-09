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
    private var focusGeneration = 0

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

    func focus(_ source: SCWindow) async throws {
        try Task.checkCancellation()
        focusGeneration += 1
        let generation = focusGeneration
        guard AXIsProcessTrusted() else { throw RequestError.message("需要辅助功能权限才能定位来源窗口。") }
        guard let owner = source.owningApplication,
              let app = NSRunningApplication(processIdentifier: owner.processID), !app.isTerminated else {
            throw RequestError.message("来源应用已经退出。")
        }
        let root = AXUIElementCreateApplication(owner.processID)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &result) == .success,
              let windows = result as? [AXUIElement], !windows.isEmpty else {
            throw RequestError.message("来源应用没有提供可定位的窗口，请确认窗口仍然打开。")
        }
        let currentInfo = CGWindowListCopyWindowInfo(.optionIncludingWindow, source.windowID) as? [[String: Any]]
        guard let entry = currentInfo?.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == source.windowID }) else {
            throw RequestError.message("来源窗口已经关闭。")
        }
        guard entry[kCGWindowOwnerPID as String] as? pid_t == owner.processID,
              let target = try windows.first(where: { try WindowActivation.windowID(of: $0) == source.windowID }) else {
            throw RequestError.message("来源应用没有提供对应窗口的辅助功能对象。")
        }
        if app.isHidden {
            try set(root, kAXHiddenAttribute, kCFBooleanFalse, operation: "显示来源应用")
        }
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &minimized) == .success,
           minimized as? Bool == true {
            try set(target, kAXMinimizedAttribute, kCFBooleanFalse, operation: "恢复来源窗口")
        }
        try set(target, kAXMainAttribute, kCFBooleanTrue, operation: "选择来源窗口")
        try WindowActivation.bringForward(processID: owner.processID, windowID: source.windowID)
        try raise(target)
        app.activate(options: [.activateAllWindows])

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            try Task.checkCancellation()
            guard generation == focusGeneration else { throw CancellationError() }
            guard !app.isTerminated else { throw RequestError.message("来源应用已经退出。") }
            var focused: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &focused)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == owner.processID,
               read == .success, let focused, CFEqual(focused, target) { return }
            guard ContinuousClock.now < deadline else {
                throw RequestError.message("来源窗口尚未获得焦点，请检查来源应用是否有阻塞操作的对话框。")
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef, operation: String) throws {
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        guard status == .success else { throw RequestError.message("\(operation)失败（辅助功能错误 \(status.rawValue)）。") }
    }

    private func raise(_ window: AXUIElement) throws {
        let status = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        guard status == .success else { throw RequestError.message("置前来源窗口失败（辅助功能错误 \(status.rawValue)）。") }
    }

    private func matchScore(_ element: AXUIElement, _ window: SCWindow, frame: CGRect? = nil, title: String? = nil) -> Double {
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
        let titlePenalty: Double = (titleValue as? String) == (title ?? window.title) ? 0 : 1
        let target = frame ?? window.frame
        return titlePenalty + abs(position.x - target.minX) + abs(position.y - target.minY)
            + abs(size.width - target.width) + abs(size.height - target.height)
    }
}
#endif
