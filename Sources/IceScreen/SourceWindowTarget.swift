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
            throw RequestError.message("来源应用已经退出或重新启动。")
        }
        let entries = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        if let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }) {
            guard entry[kCGWindowOwnerPID as String] as? pid_t == processID else {
                throw RequestError.message("来源窗口身份已经失效。")
            }
            return entry
        }
        // 隐藏、最小化时 WindowServer 列表也可能暂时省略窗口，须查询真实 AX 对象的存活状态。
        guard try resolveElement() != nil else {
            Self.log.error("Source identity absent from WindowServer and AX: PID=\(self.processID), window=\(self.windowID), hidden=\(application.isHidden)")
            throw RequestError.message("来源窗口已经关闭。")
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
            if AXUIElementGetPid(retainedElement, &pid) == .success, pid == processID {
                // 该对象已按原 PID 和窗口 ID 验证；存活检查保留捕获时的 ID 关联。
                if status == .success, role as? String == kAXWindowRole { return retainedElement }
                if status == .cannotComplete {
                    pending = SourceFocusPending(operation: "读取保留来源窗口的存活状态")
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
        if status == .cannotComplete { throw pending ?? SourceFocusPending(operation: "读取来源应用窗口列表") }
        if status == .noValue {
            if let pending { throw pending }
            return nil
        }
        guard status == .success else {
            throw RequestError.message("读取来源窗口对象失败（辅助功能错误 \(status.rawValue)）。")
        }
        guard let elements = result as? [AXUIElement] else {
            throw RequestError.message("来源应用返回了无效的窗口列表。")
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
                pending = SourceFocusPending(operation: "读取枚举来源窗口的存活状态")
                continue
            }
            guard roleStatus == .success, role as? String == kAXWindowRole else { continue }
            retainedElement = element
            resolutionState = "resolved_exact_window=\(windowID)"
            return element
        }
        if let pending { throw pending }
        // 非当前 Space 的窗口可以暂时不出现在 AXWindows 中。
        return nil
    }
}
#endif
