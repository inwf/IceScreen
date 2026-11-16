#if os(macOS)
import AppKit
import ScreenCaptureKit
import ApplicationServices
import OSLog
import IceCore

@MainActor
final class WindowCatalog: ObservableObject {
    private static let focusLog = Logger(subsystem: "org.icescreen.app", category: "SourceFocus")
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

    func focus(_ source: SCWindow, retainedTarget: SourceWindowTarget? = nil) async throws {
        try Task.checkCancellation()
        focusGeneration += 1
        let generation = focusGeneration
        guard AXIsProcessTrusted() else { throw RequestError.message("需要辅助功能权限才能定位来源窗口。") }
        guard let owner = source.owningApplication else {
            throw RequestError.message("来源应用已经退出。")
        }
        let reference = retainedTarget ?? SourceWindowTarget(source)
        guard reference.processID == owner.processID, reference.windowID == source.windowID else {
            throw RequestError.message("来源窗口标识与捕获会话不一致。")
        }
        guard let app = reference.application else { throw RequestError.message("来源应用已经退出。") }
        let root = reference.root
        var unhideRequested = false
        var restoreRequested = false
        var selectionReady = false
        func prepare(_ target: AXUIElement) throws {
            var minimized: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &minimized)
            if status == .cannotComplete { throw SourceFocusPending(operation: "读取来源窗口最小化状态") }
            if status == .success, minimized as? Bool == true {
                if !restoreRequested {
                    try set(target, kAXMinimizedAttribute, kCFBooleanFalse, operation: "恢复来源窗口")
                    restoreRequested = true
                }
                throw SourceFocusPending(operation: "等待来源窗口完成恢复")
            }
            try set(target, kAXMainAttribute, kCFBooleanTrue, operation: "选择来源窗口")
        }
        func selectKeyboardFocus(_ target: AXUIElement) throws {
            var writable: DarwinBoolean = false
            let status = AXUIElementIsAttributeSettable(root, kAXFocusedWindowAttribute as CFString, &writable)
            if status == .attributeUnsupported { return }
            if status == .cannotComplete { throw SourceFocusPending(operation: "检查来源窗口焦点接口") }
            guard status == .success else {
                throw RequestError.message("检查来源窗口焦点接口失败（辅助功能错误 \(status.rawValue)）。")
            }
            if writable.boolValue {
                try set(root, kAXFocusedWindowAttribute, target, operation: "聚焦来源窗口")
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var nextActivation = ContinuousClock.now
        var pendingOperation = ""
        var confirmedSince: ContinuousClock.Instant?
        while true {
            try Task.checkCancellation()
            guard generation == focusGeneration else { throw CancellationError() }
            var focusedID: CGWindowID?
            var read = AXError.noValue
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            var onScreen = false
            var onVisibleSpace = false
            do {
                let entry = try reference.validate()
                onScreen = entry?[kCGWindowIsOnscreen as String] as? Bool == true
                onVisibleSpace = try WindowActivation.isOnVisibleSpace(source.windowID)
                var activatedByID = false
                if ContinuousClock.now >= nextActivation, (!onScreen || !onVisibleSpace), !app.isHidden {
                    // 先请求返回来源 Space，使暂时不可响应的 AX 对象重新可用。
                    try WindowActivation.bringForward(processID: owner.processID, windowID: source.windowID)
                    app.activate(options: [.activateAllWindows])
                    activatedByID = true
                }
                let target = try reference.resolveElement()
                if ContinuousClock.now >= nextActivation {
                    selectionReady = false
                    if app.isHidden {
                        if !unhideRequested {
                            try set(root, kAXHiddenAttribute, kCFBooleanFalse, operation: "显示来源应用")
                            unhideRequested = true
                        }
                        throw SourceFocusPending(operation: "等待显示来源应用")
                    }
                    if let target { try prepare(target); selectionReady = true }
                    // 来源身份已验证，跨 Space 请求不依赖当前 AX 窗口列表。
                    if !activatedByID {
                        try WindowActivation.bringForward(processID: owner.processID, windowID: source.windowID)
                        app.activate(options: [.activateAllWindows])
                    }
                    if let target { try raise(target) }
                    nextActivation = ContinuousClock.now.advanced(by: .milliseconds(500))
                }
                if let target, selectionReady {
                    var focused: CFTypeRef?
                    read = AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &focused)
                    if read == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                        focusedID = try WindowActivation.windowID(of: unsafeBitCast(focused, to: AXUIElement.self))
                    }
                    if frontmostPID == owner.processID, onScreen, onVisibleSpace, focusedID == source.windowID {
                        if let confirmedSince, ContinuousClock.now - confirmedSince >= .milliseconds(100) { return }
                        if confirmedSince == nil { confirmedSince = ContinuousClock.now }
                    } else {
                        confirmedSince = nil
                    }
                    if frontmostPID == owner.processID, onScreen, onVisibleSpace, focusedID != source.windowID {
                        try selectKeyboardFocus(target)
                    }
                } else {
                    confirmedSince = nil
                }
            } catch let pending as SourceFocusPending {
                confirmedSince = nil
                pendingOperation = pending.operation
                nextActivation = ContinuousClock.now.advanced(by: .milliseconds(100))
            }
            guard ContinuousClock.now < deadline else {
                Self.focusLog.error("Source focus timeout: expectedPID=\(owner.processID), expectedWindow=\(source.windowID), frontmostPID=\(frontmostPID), focusedWindow=\(focusedID ?? 0), onScreen=\(onScreen), axStatus=\(read.rawValue)")
                let foreground = NSWorkspace.shared.frontmostApplication
                Self.focusLog.error("Foreground application: \(foreground?.bundleIdentifier ?? "unknown", privacy: .public), name=\(foreground?.localizedName ?? "unknown", privacy: .public)")
                Self.focusLog.error("Pending Accessibility transition: \(pendingOperation, privacy: .public)")
                Self.focusLog.error("Source window on a currently visible Space: \(onVisibleSpace)")
                throw RequestError.message("尚未返回来源窗口所在桌面，请检查来源应用是否有阻塞操作的对话框。")
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef, operation: String) throws {
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        if status == .cannotComplete { throw SourceFocusPending(operation: operation) }
        guard status == .success else { throw RequestError.message("\(operation)失败（辅助功能错误 \(status.rawValue)）。") }
    }

    private func raise(_ window: AXUIElement) throws {
        let status = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        if status == .cannotComplete { throw SourceFocusPending(operation: "置前来源窗口") }
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
