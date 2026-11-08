#if os(macOS)
import AppKit
import ApplicationServices
import IceCore

@MainActor
final class HotkeyMonitor {
    var shortcut = Shortcut()
    var recording = false
    var onCapture: ((Bool) -> Void)?
    var onQuickRegion: ((CGPoint) -> Void)?
    var onFunctionTap: (() -> Void)?
    var onHoverKey: ((UInt16) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var functionDown: TimeInterval?
    private var functionUsed = false
    private var consumedKeys: Set<UInt16> = []

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard !recording else { return false }
        let flags = event.flags
        let function = flags.contains(.maskSecondaryFn)
        if type == .flagsChanged {
            if function, functionDown == nil {
                functionDown = ProcessInfo.processInfo.systemUptime
                functionUsed = false
            } else if !function, let pressed = functionDown {
                if !functionUsed, ProcessInfo.processInfo.systemUptime - pressed < 0.45 { onFunctionTap?() }
                functionDown = nil
            }
            return false
        }
        if type == .leftMouseDown {
            if function {
                functionUsed = true
                if event.getIntegerValueField(.mouseEventClickState) == 2 { onQuickRegion?(event.location); return true }
            }
            return false
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp { return consumedKeys.remove(code) != nil }
        if function { functionUsed = true }
        let matches = code == shortcut.keyCode
            && flags.contains(.maskCommand) == shortcut.command
            && flags.contains(.maskAlternate) == shortcut.option
            && flags.contains(.maskControl) == shortcut.control
            && function == shortcut.function
        if matches {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { onCapture?(flags.contains(.maskShift)) }
            consumedKeys.insert(code)
            return true
        }
        if flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]).isEmpty,
           onHoverKey?(code) == true {
            consumedKeys.insert(code)
            return true
        }
        return false
    }
}
#endif
