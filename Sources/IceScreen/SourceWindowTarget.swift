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

    func validate() throws -> [String: Any] {
        guard let application, !application.isTerminated,
              let current = NSRunningApplication(processIdentifier: processID), !current.isTerminated,
              current.launchDate == launchedAt else {
            throw RequestError.message("来源应用已经退出或重新启动。")
        }
        let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]] ?? []
        guard let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }),
              entry[kCGWindowOwnerPID as String] as? pid_t == processID else {
            throw RequestError.message("来源窗口已经关闭。")
        }
        return entry
    }

    func resolveElement() throws -> AXUIElement? {
        if let retainedElement {
            var pid: pid_t = 0
            if AXUIElementGetPid(retainedElement, &pid) == .success, pid == processID,
               try WindowActivation.windowID(of: retainedElement) == windowID {
                return retainedElement
            }
            self.retainedElement = nil
        }
        var result: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &result)
        if status == .noValue || status == .cannotComplete { return nil }
        guard status == .success else {
            throw RequestError.message("读取来源窗口对象失败（辅助功能错误 \(status.rawValue)）。")
        }
        guard let elements = result as? [AXUIElement] else { return nil }
        for element in elements where try WindowActivation.windowID(of: element) == windowID {
            AXUIElementSetMessagingTimeout(element, 0.25)
            retainedElement = element
            return element
        }
        // 非当前 Space 的窗口可以暂时不出现在 AXWindows 中。
        return nil
    }
}
#endif
