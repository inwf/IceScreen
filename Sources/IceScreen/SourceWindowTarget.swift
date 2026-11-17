#if os(macOS)
import AppKit
import ApplicationServices
import ScreenCaptureKit
import OSLog
import IceCore

@MainActor
final class SourceWindowTarget {
    private static let log = Logger(subsystem: "org.icescreen.app", category: "SourceFocus")
    let windowID: CGWindowID
    let processID: pid_t
    let application: NSRunningApplication?
    let root: AXUIElement
    private let launchedAt: Date?
    private var hasInvalidatedElement = false
    private(set) var retainedElement: AXUIElement?
    private(set) var resolutionState = "not_resolved"

    init(_ source: SCWindow) {
        windowID = source.windowID
        processID = source.owningApplication?.processID ?? 0
        application = NSRunningApplication(processIdentifier: processID)
        launchedAt = application?.launchDate
        root = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(root, 0.25)
        if AXIsProcessTrusted() {
            do { _ = try resolveElement() }
            catch { Self.log.debug("Capture-time source target retention unavailable: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func validate() throws -> [String: Any]? {
        guard let application, !application.isTerminated,
              let current = NSRunningApplication(processIdentifier: processID), !current.isTerminated,
              current.launchDate == launchedAt else {
            throw RequestError.message(L10n.text("来源应用已经退出或重新启动。", "The source app has quit or restarted."))
        }
        let entries = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        if let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }) {
            guard entry[kCGWindowOwnerPID as String] as? pid_t == processID else {
                throw RequestError.message(L10n.text("来源窗口身份已经失效。", "The source window identity is no longer valid."))
            }
            return entry
        }
        // 隐藏、最小化时 WindowServer 列表也可能暂时省略窗口，须查询真实 AX 对象的存活状态。
        guard try resolveElement() != nil else {
            Self.log.error("Source identity absent from WindowServer and AX: PID=\(self.processID), window=\(self.windowID), hidden=\(application.isHidden)")
            throw RequestError.message(L10n.text("来源窗口已经关闭。", "The source window has closed."))
        }
        return nil
    }

    func resolveElement() throws -> AXUIElement? {
        resolutionState = "not_retained"
        var pending: SourceFocusPending?
        if let retainedElement {
            var pid: pid_t = 0
            var role: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(retainedElement, kAXRoleAttribute as CFString, &role)
            resolutionState = "retained_role=\(status.rawValue)"
            if status == .invalidUIElement { hasInvalidatedElement = true }
            if AXUIElementGetPid(retainedElement, &pid) == .success, pid == processID {
                // 该对象已按原 PID 和窗口 ID 验证；存活检查保留捕获时的 ID 关联。
                if status == .success, role as? String == kAXWindowRole { return retainedElement }
                if status == .cannotComplete {
                    pending = SourceFocusPending(operation: L10n.text("读取保留来源窗口的存活状态", "Read retained source window liveness"))
                } else {
                    self.retainedElement = nil
                }
            } else {
                self.retainedElement = nil
            }
        }
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &result)
        resolutionState += ", list=\(status.rawValue)"
        var elements: [AXUIElement] = []
        if status == .cannotComplete {
            pending = pending ?? SourceFocusPending(operation: L10n.text("读取来源应用窗口列表", "Read source app window list"))
        } else if status == .success {
            guard let listed = result as? [AXUIElement] else {
                throw RequestError.message(L10n.text("来源应用返回了无效的窗口列表。", "The source app returned an invalid window list."))
            }
            elements = listed
        } else if status != .noValue {
            throw RequestError.message(L10n.text("读取来源窗口对象失败（辅助功能错误 \(status.rawValue)）。", "Unable to read source window element (accessibility error \(status.rawValue))."))
        }

        // Terminal 的非当前 Space 窗口可从 AXFocusedWindow 取得，仍须核对原 PID、窗口 ID 和 role。
        var focused: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &focused)
        resolutionState += ", focused=\(focusedStatus.rawValue)"
        if focusedStatus == .success {
            guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                throw RequestError.message(L10n.text("来源应用返回了无效的焦点窗口对象。", "The source app returned an invalid focused window element."))
            }
            let element = unsafeBitCast(focused, to: AXUIElement.self)
            if !elements.contains(where: { CFEqual($0, element) }) { elements.append(element) }
        } else if focusedStatus == .cannotComplete {
            pending = pending ?? SourceFocusPending(operation: L10n.text("读取来源应用焦点窗口对象", "Read source app focused window element"))
        } else if focusedStatus != .noValue, focusedStatus != .attributeUnsupported {
            throw RequestError.message(L10n.text("读取来源焦点窗口对象失败（辅助功能错误 \(focusedStatus.rawValue)）。", "Unable to read source focused window element (accessibility error \(focusedStatus.rawValue))."))
        }
        resolutionState += ", candidates=\(elements.count)"
        for element in elements {
            AXUIElementSetMessagingTimeout(element, 0.25)
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, pid == processID else { continue }
            do {
                guard try WindowActivation.windowID(of: element) == windowID else { continue }
            } catch let transition as SourceFocusPending {
                pending = transition
                continue
            }
            var role: CFTypeRef?
            let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if roleStatus == .cannotComplete {
                pending = SourceFocusPending(operation: L10n.text("读取枚举来源窗口的存活状态", "Read enumerated source window liveness"))
                continue
            }
            guard roleStatus == .success, role as? String == kAXWindowRole else { continue }
            retainedElement = element
            hasInvalidatedElement = false
            resolutionState = "resolved_exact_window=\(windowID)"
            return element
        }
        if let pending { throw pending }
        // 已失效的原 AX 对象没有同 ID 替代对象，且窗口已脱离所有桌面。
        if hasInvalidatedElement, try WindowActivation.spaceIDs(for: windowID).isEmpty {
            throw RequestError.message(L10n.text("来源窗口已经关闭。", "The source window has closed."))
        }
        // 非当前 Space 的窗口可以暂时不出现在 AXWindows 中。
        return nil
    }
}
#endif
