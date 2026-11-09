#if os(macOS)
import AppKit
import ApplicationServices
import IceCore

@MainActor
final class HotkeyMonitor {
    var shortcut = Shortcut()
    var regionShortcut: Shortcut? = Shortcut().regionVariant
    var closeAllShortcut: Shortcut?
    var quickRegionCapture = true
    var triggerModifier: TriggerModifier = .function { didSet { functionGesture.reset(); cancelPendingTap() } }
    var recording = false { didSet { functionGesture.reset(); cancelPendingTap() } }
    var onCapture: ((Bool) -> Void)?
    var onQuickRegion: ((CGPoint) -> Void)?
    var onFunctionTap: (() -> Void)?
    var onFunctionDoubleTap: (() -> Void)?
    var onCloseAll: (() -> Void)?
    var onHoverAction: ((HoverAction) -> Bool)?
    var onSpaceDown: (() -> Bool)?
    var onSpaceUp: (() -> Void)?
    var onSpaceCancel: (() -> Void)?
    var onEscape: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var functionGesture = FunctionKeyGesture()
    private var consumedKeys: Set<UInt16> = []
    private var previewKeyHeld = false
    private var consumedMouseDown = false
    private var taps = ModifierTapSequence(interval: NSEvent.doubleClickInterval)
    private var singleTapTask: Task<Void, Never>?

    private func cancelPendingTap() {
        singleTapTask?.cancel()
        singleTapTask = nil
        taps.reset()
    }

    private func registerTap() {
        singleTapTask?.cancel()
        if taps.tap(at: ProcessInfo.processInfo.systemUptime) {
            DispatchQueue.main.async { [weak self] in self?.onFunctionDoubleTap?() }
        } else {
            singleTapTask = Task { [weak self] in
                guard let self else { return }
                do { try await Task.sleep(for: .seconds(self.taps.interval)) } catch { return }
                if self.taps.takeSingle(at: ProcessInfo.processInfo.systemUptime) { self.onFunctionTap?() }
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp]
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
        functionGesture.reset()
        consumedKeys.removeAll()
        if previewKeyHeld { onSpaceCancel?(); previewKeyHeld = false }
        consumedMouseDown = false
        cancelPendingTap()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            functionGesture.reset()
            consumedKeys.removeAll()
            if previewKeyHeld { onSpaceCancel?(); previewKeyHeld = false }
            consumedMouseDown = false
            cancelPendingTap()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            let consumed = consumedKeys.remove(code) != nil
            if code == 49, previewKeyHeld {
                previewKeyHeld = false
                onSpaceUp?()
            }
            return consumed
        }
        if type == .leftMouseUp {
            defer { consumedMouseDown = false }
            return consumedMouseDown
        }
        guard !recording else { return false }
        let flags = event.flags
        let function = flags.contains(.maskSecondaryFn)
        let triggerFlag: CGEventFlags
        switch triggerModifier {
        case .function: triggerFlag = .maskSecondaryFn
        case .shift: triggerFlag = .maskShift
        case .control: triggerFlag = .maskControl
        case .option: triggerFlag = .maskAlternate
        case .command: triggerFlag = .maskCommand
        }
        let triggerHeld = flags.contains(triggerFlag)
        let otherFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]
        let otherModifiers = !flags.intersection(otherFlags.subtracting(triggerFlag)).isEmpty
        if type == .flagsChanged {
            if otherModifiers { cancelPendingTap() }
            if functionGesture.flagsChanged(function: triggerHeld, otherModifiers: otherModifiers,
                                            at: ProcessInfo.processInfo.systemUptime) {
                registerTap()
            }
            return false
        }
        if type == .leftMouseDown {
            if triggerHeld {
                functionGesture.consume()
                cancelPendingTap()
                if quickRegionCapture, !otherModifiers, event.getIntegerValueField(.mouseEventClickState) == 2 {
                    let point = event.location
                    consumedMouseDown = true
                    DispatchQueue.main.async { [weak self] in self?.onQuickRegion?(point) }
                    return true
                }
            }
            return false
        }
        functionGesture.consume()
        cancelPendingTap()
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if code == 53, !repeated, onEscape?() == true { consumedKeys.insert(code); return true }
        func matches(_ key: Shortcut?) -> Bool {
            key?.matches(keyCode: code, command: flags.contains(.maskCommand), option: flags.contains(.maskAlternate),
                         control: flags.contains(.maskControl), function: function, shift: flags.contains(.maskShift)) == true
        }
        if matches(closeAllShortcut) {
            if !repeated { DispatchQueue.main.async { [weak self] in self?.onCloseAll?() } }
            consumedKeys.insert(code)
            return true
        }
        let region = matches(regionShortcut)
        if region || matches(shortcut) {
            if !repeated {
                DispatchQueue.main.async { [weak self] in self?.onCapture?(region) }
            }
            consumedKeys.insert(code)
            return true
        }
        if code == 49, flags.intersection(otherFlags).isEmpty {
            if consumedKeys.contains(code) { return true }
            if !repeated, onSpaceDown?() == true {
                previewKeyHeld = true
                consumedKeys.insert(code)
                return true
            }
        }
        // macOS 为方向键自身附加 secondaryFn，不能把它当成用户按住 fn。
        let hoverModifiers: CGEventFlags = code == 123 || code == 124
            ? [.maskCommand, .maskAlternate, .maskControl]
            : [.maskCommand, .maskAlternate, .maskControl, .maskSecondaryFn]
        if flags.intersection(hoverModifiers).isEmpty,
           let action = HoverAction.resolve(keyCode: code, repeated: repeated), onHoverAction?(action) == true {
            consumedKeys.insert(code)
            return true
        }
        return repeated && consumedKeys.contains(code)
    }
}
#endif
