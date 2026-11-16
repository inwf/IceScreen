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
        func minimized(_ target: AXUIElement) throws -> Bool {
            var minimized: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &minimized)
            if status == .cannotComplete { throw SourceFocusPending(operation: "读取来源窗口最小化状态") }
            if status == .attributeUnsupported { return false }
            guard status == .success, let value = minimized as? Bool else {
                throw RequestError.message("读取来源窗口最小化状态失败（辅助功能错误 \(status.rawValue)）。")
            }
            return value
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
        var progress = SourceFocusProgress(processID: owner.processID, windowID: source.windowID,
                                          startedAt: ProcessInfo.processInfo.systemUptime)
        var pendingOperation = ""
        while true {
            try Task.checkCancellation()
            guard generation == focusGeneration else { throw CancellationError() }
            let attempt = progress.beginAttempt(at: ProcessInfo.processInfo.systemUptime)
            var read = AXError.noValue
            var observation = SourceFocusProgress.Observation(
                foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                focusedWindowID: nil, onScreen: false, onVisibleSpace: false, hidden: app.isHidden, minimized: nil)
            pendingOperation = ""
            do {
                let entry = try reference.validate()
                observation.onScreen = entry?[kCGWindowIsOnscreen as String] as? Bool == true
                observation.onVisibleSpace = try WindowActivation.isOnVisibleSpace(source.windowID)
                if app.isHidden {
                    if attempt {
                        try set(root, kAXHiddenAttribute, kCFBooleanFalse, operation: "显示来源应用")
                    }
                    throw SourceFocusPending(operation: "等待显示来源应用")
                }
                if attempt, !observation.onScreen || !observation.onVisibleSpace {
                    // 先请求返回来源 Space，使暂时不可响应的 AX 对象重新可用。
                    try WindowActivation.bringForward(processID: owner.processID, windowID: source.windowID)
                }
                guard let target = try reference.resolveElement() else {
                    throw SourceFocusPending(operation: "等待来源窗口对象重新可用")
                }
                observation.minimized = try minimized(target)
                if observation.minimized == true {
                    if attempt {
                        try set(target, kAXMinimizedAttribute, kCFBooleanFalse, operation: "恢复来源窗口")
                    }
                    throw SourceFocusPending(operation: "等待来源窗口完成恢复")
                }
                if attempt {
                    Self.focusLog.debug("Selecting exact source: PID=\(owner.processID), window=\(source.windowID), resolution=\(reference.resolutionState, privacy: .public)")
                    // 应用激活在精确窗口选择之前完成，避免覆盖后续交付的目标焦点。
                    if !app.isActive { app.activate(options: []) }
                    try set(target, kAXMainAttribute, kCFBooleanTrue, operation: "选择来源窗口")
                    try WindowActivation.bringForward(processID: owner.processID, windowID: source.windowID)
                    try raise(target)
                    try selectKeyboardFocus(target)
                }

                var focused: CFTypeRef?
                read = AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &focused)
                if read == .cannotComplete { throw SourceFocusPending(operation: "读取来源应用键盘焦点") }
                if read == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
                    let element = unsafeBitCast(focused, to: AXUIElement.self)
                    AXUIElementSetMessagingTimeout(element, 0.25)
                    do {
                        observation.focusedWindowID = try WindowActivation.windowID(of: element)
                    } catch is SourceFocusPending {
                        throw SourceFocusPending(operation: "读取当前键盘焦点窗口标识")
                    }
                } else if read != .noValue {
                    throw RequestError.message("读取来源应用键盘焦点失败（辅助功能错误 \(read.rawValue)）。")
                }
                observation.foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                observation.hidden = app.isHidden
                if progress.observe(observation, at: ProcessInfo.processInfo.systemUptime) { return }
            } catch let pending as SourceFocusPending {
                progress.pending()
                pendingOperation = pending.operation
            }
            guard !progress.expired(at: ProcessInfo.processInfo.systemUptime) else {
                Self.focusLog.error("Source focus timeout: expectedPID=\(owner.processID), expectedWindow=\(source.windowID), frontmostPID=\(observation.foregroundPID ?? 0), focusedWindow=\(observation.focusedWindowID ?? 0), onScreen=\(observation.onScreen), axStatus=\(read.rawValue)")
                let foreground = NSWorkspace.shared.frontmostApplication
                Self.focusLog.error("Foreground application: \(foreground?.bundleIdentifier ?? "unknown", privacy: .public), name=\(foreground?.localizedName ?? "unknown", privacy: .public)")
                Self.focusLog.error("Pending Accessibility transition: \(pendingOperation, privacy: .public)")
                Self.focusLog.error("Source window on a currently visible Space: \(observation.onVisibleSpace), resolution=\(reference.resolutionState, privacy: .public)")
                switch progress.failure(for: observation) {
                case .hidden: throw RequestError.message("来源应用仍处于隐藏状态，无法定位捕获的窗口。")
                case .minimized: throw RequestError.message("来源窗口未能完成最小化恢复。")
                case .space: throw RequestError.message("尚未返回来源窗口所在桌面。")
                case .foreground: throw RequestError.message("来源应用未能切换到前台。")
                case .keyboardFocus: throw RequestError.message("来源应用已经显示，但未能将键盘焦点交给捕获的窗口。")
                case .accessibility: throw RequestError.message("来源应用未能及时提供可验证的窗口焦点。")
                case nil: throw RequestError.message("来源窗口焦点未能保持稳定。")
                }
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
