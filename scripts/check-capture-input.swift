import AppKit
import ApplicationServices
import IceCore

@main
enum CaptureInputChecks {
    @MainActor static func main() {
        precondition(AXIsProcessTrusted(), "Capture input checks require Accessibility permission.")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            do { try await run(); app.terminate(nil) }
            catch { fputs("Capture input check failed: \(error)\n", stderr); exit(1) }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        guard let screen = NSScreen.main else { fatalError("An active WindowServer session is required.") }
        let window = NSWindow(contentRect: CGRect(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY,
                                                 width: 200, height: 140),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "IceScreen capture input check"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let screenPoint = window.convertPoint(toScreen: CGPoint(x: 80, y: 60))
        let point = CGPoint(x: screenPoint.x, y: NSScreen.screens[0].frame.maxY - screenPoint.y)
        let observer = DeliveredMouseEvents()
        observer.start()
        defer { observer.stop() }
        let monitor = HotkeyMonitor()
        monitor.quickCaptureModifiers = [.command, .shift]
        var captures = 0
        monitor.onQuickRegion = { capturedPoint in
            precondition(hypot(capturedPoint.x - point.x, capturedPoint.y - point.y) < 1)
            captures += 1
        }
        precondition(monitor.start(), "Could not install the real capture event tap.")
        defer { monitor.stop() }
        let source = CGEventSource(stateID: .privateState)!
        let originalPointer = CGEvent(source: nil)!.location
        defer {
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: originalPointer,
                    mouseButton: .left)!.post(tap: .cgSessionEventTap)
        }
        let chord: CGEventFlags = [.maskCommand, .maskShift]
        func post(_ type: CGEventType, count: Int64 = 1, flags: CGEventFlags = [.maskCommand, .maskShift],
                  offset: CGFloat = 0) {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: CGPoint(x: point.x + offset, y: point.y), mouseButton: .left)!
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState, value: count)
            event.post(tap: .cgSessionEventTap)
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(30)) }
        func click(_ count: Int64 = 1, flags: CGEventFlags = [.maskCommand, .maskShift]) async throws {
            post(.leftMouseDown, count: count, flags: flags); try await settle()
            post(.leftMouseUp, count: count, flags: flags); try await settle()
        }
        func expect(_ types: [CGEventType]) {
            precondition(observer.types == types, "Unexpected downstream mouse events: \(observer.types)")
            observer.types.removeAll()
        }
        try await click()
        expect([])
        try await click(2)
        expect([])
        precondition(captures == 1, "An exact chord must capture once without forwarding either click.")

        try await click()
        try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
        expect([.leftMouseDown, .leftMouseUp])
        precondition(observer.lastFlags == chord, "Deferred single clicks must retain the original modifiers.")

        for flags: CGEventFlags in [[], .maskCommand, [.maskCommand, .maskShift, .maskAlternate]] {
            try await click(flags: flags); try await click(2, flags: flags)
            expect([.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        }
        precondition(captures == 1, "Other combinations must retain the application's double click.")

        post(.leftMouseDown); try await settle()
        post(.leftMouseDragged, offset: 12); try await settle()
        post(.leftMouseUp, offset: 12); try await settle()
        expect([.leftMouseDown, .leftMouseDragged, .leftMouseUp])

        try await click()
        monitor.recording = true
        try await settle()
        expect([.leftMouseDown, .leftMouseUp])
        try await click(); try await click(2)
        expect([.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp])
        monitor.recording = false

        try await click()
        monitor.quickCaptureModifiers = .function
        try await settle()
        expect([.leftMouseDown, .leftMouseUp])
        try await click(2)
        expect([.leftMouseDown, .leftMouseUp])
        precondition(captures == 1)

        monitor.quickCaptureModifiers = [.command, .shift]
        try await click()
        monitor.stop()
        try await settle()
        expect([.leftMouseDown, .leftMouseUp])
        print("Passed native event-tap double-click isolation, exact combinations, deferred singles, dragging, recording, settings changes and shutdown checks.")
    }
}

@MainActor
private final class DeliveredMouseEvents {
    var types: [CGEventType] = []
    var lastFlags: CGEventFlags = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        let mask = [CGEventType.leftMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                               eventsOfInterest: mask, callback: { _, type, event, context in
            MainActor.assumeIsolated {
                let observer = Unmanaged<DeliveredMouseEvents>.fromOpaque(context!).takeUnretainedValue()
                if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier) {
                    observer.types.append(type)
                    observer.lastFlags = event.flags
                }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        precondition(tap != nil, "Could not install downstream event observation.")
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap!, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source!, .commonModes)
        CGEvent.tapEnable(tap: tap!, enable: true)
    }
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
}
