#if os(macOS)
import AppKit
import ApplicationServices
import IceCore

@MainActor
final class HotkeyMonitor {
    var shortcut = Shortcut()
    var regionShortcut: Shortcut? = Shortcut().regionVariant
    var closeAllShortcut: Shortcut?
    var quickRegionCapture = true { didSet { if oldValue != quickRegionCapture { flushPendingClicks() } } }
    var quickCaptureModifiers: QuickCaptureModifiers = .function {
        didSet { if oldValue != quickCaptureModifiers { flushPendingClicks() } }
    }
    var canQuickCapture: ((CGPoint) -> Bool)?
    var triggerModifier: TriggerModifier = .function {
        didSet { functionGesture.reset(); cancelPendingTap(); flushPendingClicks() }
    }
    var recording = false {
        didSet { functionGesture.reset(); cancelPendingTap(); flushPendingClicks() }
    }
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
    private var clicks = QuickCaptureClickGate<CGEvent>(interval: NSEvent.doubleClickInterval)
    private var clickTimer: Timer?
    private static let replayMarker: Int64 = 0x494345434C49434B
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
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
                    .leftMouseDragged, .mouseMoved, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { proxy, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handle(type: type, event: event, proxy: proxy) ? nil : Unmanaged.passUnretained(event)
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
        replay(clicks.reset())
        updateClickTimer()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        functionGesture.reset()
        consumedKeys.removeAll()
        if previewKeyHeld { onSpaceCancel?(); previewKeyHeld = false }
        cancelPendingTap()
    }

    private func flushPendingClicks() {
        replay(clicks.flush())
        updateClickTimer()
    }

    private func replay(_ events: [CGEvent], proxy: CGEventTapProxy? = nil) {
        for event in events {
            if let proxy { event.tapPostEvent(proxy) }
            else {
                event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
                event.post(tap: .cgSessionEventTap)
            }
        }
    }

    private func updateClickTimer() {
        clickTimer?.invalidate()
        clickTimer = nil
        guard let deadline = clicks.deadline else { return }
        let timer = Timer(timeInterval: max(0, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.replay(self.clicks.expire(at: ProcessInfo.processInfo.systemUptime))
                self.updateClickTimer()
            }
        }
        clickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handle(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            replay(clicks.reset(), proxy: proxy)
            updateClickTimer()
            functionGesture.reset()
            consumedKeys.removeAll()
            if previewKeyHeld { onSpaceCancel?(); previewKeyHeld = false }
            cancelPendingTap()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
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
        let input: QuickCaptureClickGate<CGEvent>.Input
        switch type {
        case .leftMouseDown: input = .down
        case .leftMouseUp: input = .up
        case .leftMouseDragged: input = .dragged
        case .mouseMoved: input = .moved
        default: input = .interrupt
        }
        let previousDeadline = clicks.deadline
        let held = QuickCaptureModifiers(command: flags.contains(.maskCommand), option: flags.contains(.maskAlternate),
                                         control: flags.contains(.maskControl), shift: flags.contains(.maskShift), function: function)
        var eligible = !recording && quickRegionCapture && quickCaptureModifiers.matches(held)
        if eligible && type == .leftMouseDown { eligible = canQuickCapture?(event.location) ?? true }
        let decision = clicks.handle(input, event: event.copy()!, at: ProcessInfo.processInfo.systemUptime,
                                     position: event.location, eligible: eligible,
                                     clickCount: Int(event.getIntegerValueField(.mouseEventClickState)))
        replay(decision.replay, proxy: proxy)
        if clicks.deadline != previousDeadline { updateClickTimer() }
        if decision.capture {
            let point = event.location
            DispatchQueue.main.async { [weak self] in self?.onQuickRegion?(point) }
        }
        if type == .leftMouseDown, triggerHeld {
            functionGesture.consume()
            cancelPendingTap()
        }
        if decision.consume { return true }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            let consumed = consumedKeys.remove(code) != nil
            if code == 49, previewKeyHeld {
                previewKeyHeld = false
                onSpaceUp?()
            }
            return consumed
        }
        guard !recording else { return false }
        if type == .flagsChanged {
            if otherModifiers { cancelPendingTap() }
            if functionGesture.flagsChanged(function: triggerHeld, otherModifiers: otherModifiers,
                                            at: ProcessInfo.processInfo.systemUptime) {
                registerTap()
            }
            return false
        }
        guard type == .keyDown else { return false }
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
