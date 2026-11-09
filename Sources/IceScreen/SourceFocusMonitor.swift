#if os(macOS)
import AppKit
import ApplicationServices

@MainActor
final class SourceFocusMonitor {
    var onChange: ((CGWindowID?) -> Void)?
    private var observer: AXObserver?
    private var pid: pid_t?

    func observe(_ processID: pid_t) {
        guard pid != processID else { return }
        stop()
        pid = processID
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            let monitor = Unmanaged<SourceFocusMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }
        var value: AXObserver?
        guard AXObserverCreate(processID, callback, &value) == .success, let value else { return }
        observer = value
        let application = AXUIElementCreateApplication(processID)
        for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(value, application, notification as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(value), .commonModes)
    }

    func refresh() { onChange?(pid.flatMap(Self.focusedWindowID)) }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        pid = nil
    }

    static func focusedWindowID(_ pid: pid_t) -> CGWindowID? {
        var result: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(result, to: AXUIElement.self)
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?, titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        guard let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position)
        AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size)
        let entries = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let matches: [(CGWindowID, Double)] = entries.compactMap { entry in
            guard entry[kCGWindowOwnerPID as String] as? pid_t == pid,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            let distance = abs(rect.minX - position.x) + abs(rect.minY - position.y)
                + abs(rect.width - size.width) + abs(rect.height - size.height)
            guard distance < 80 else { return nil }
            let titlePenalty = (entry[kCGWindowName as String] as? String) == (titleValue as? String) ? 0.0 : 1.0
            return (id, distance + titlePenalty)
        }
        return matches.min { $0.1 < $1.1 }?.0
    }
}
#endif
