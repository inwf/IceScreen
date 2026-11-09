import AppKit
import ApplicationServices
import ScreenCaptureKit
import IceCore

@main
enum SourceFocusChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 2, arguments[0] == "--watch-source-windows" {
            SourceWindowPlacement.watch(arguments[1]); return
        }
        if arguments.count == 2, arguments[0] == "--park-and-crash" {
            app.setActivationPolicy(.accessory); app.finishLaunching()
            Task { @MainActor in
                let catalog = WindowCatalog()
                await catalog.refresh()
                guard let source = catalog.windows.first(where: { String($0.windowID) == arguments[1] }) else { exit(70) }
                do {
                    let placement = SourceWindowPlacement()
                    try placement.park(source)
                    raise(SIGKILL)
                } catch { fputs("\(error)\n", stderr); exit(71) }
            }
            app.run(); return
        }
        if arguments.first == "--fixture" {
            app.setActivationPolicy(.regular)
            app.finishLaunching()
            let windows = (1...2).map { index -> NSWindow in
                let window = NSWindow(contentRect: NSRect(x: 160 + index * 60, y: 180, width: 420, height: 280),
                                      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
                window.title = "IceScreen focus check \(index)"
                window.isReleasedWhenClosed = false
                window.makeKeyAndOrderFront(nil)
                return window
            }
            withExtendedLifetime(windows) { app.run() }
            return
        }
        precondition(arguments.count == 1, "Pass the directory containing the two fixture applications.")
        precondition(AXIsProcessTrusted(), "Source focus checks require Accessibility permission for this test executable.")
        precondition(CGPreflightScreenCaptureAccess(), "Source focus checks require Screen Recording permission.")
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            do {
                try await check(in: URL(fileURLWithPath: arguments[0]))
                print("Passed cross-process source focus, repeated clicks, double-click close, disabled clicks, and closed-source checks.")
                app.terminate(nil)
            } catch {
                fputs("Source focus check failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func check(in directory: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--fixture"]
        let sourceApp = try await NSWorkspace.shared.openApplication(at: directory.appendingPathComponent("Source.app"),
                                                                     configuration: configuration)
        defer { sourceApp.terminate() }
        let otherApp = try await NSWorkspace.shared.openApplication(at: directory.appendingPathComponent("Other.app"),
                                                                    configuration: configuration)
        defer { otherApp.terminate() }
        let catalog = WindowCatalog()
        var source: SCWindow?
        var other: SCWindow?
        for _ in 0..<60 {
            await catalog.refresh()
            if let error = catalog.error { fatalError(error) }
            source = catalog.windows.first { $0.owningApplication?.processID == sourceApp.processIdentifier
                && $0.title == "IceScreen focus check 1" }
            other = catalog.windows.first { $0.owningApplication?.processID == otherApp.processIdentifier }
            if source != nil && other != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let source, let other else { fatalError("Fixture windows did not appear in ScreenCaptureKit.") }
        var preferences = Preferences()
        preferences.autoHide = false
        preferences.clickToFocus = true
        preferences.moveSourceOffscreen = false
        let session = CaptureSession(source: source, viewport: .full, preferences: preferences, offset: 0)
        defer { session.close() }
        var confirmations = 0
        session.onFocus = { window in
            try await catalog.focus(window)
            confirmations += 1
        }
        session.panel.orderFrontRegardless()
        session.surface.layoutSubtreeIfNeeded()
        try await catalog.focus(other)
        precondition(!NSApp.isActive && !session.panel.isKeyWindow, "The content click must originate in a background panel.")

        click(session, point: NSPoint(x: 24, y: session.surface.bounds.height - 24))
        try await wait { confirmations == 1 }
        precondition(sourceApp.isActive && session.panel.isVisible, "Single click must focus the source and retain the panel.")
        precondition(focusedTitle(sourceApp) == source.title, "The captured window must be focused, including in a multi-window app.")

        for _ in 0..<3 {
            try await catalog.focus(other)
            let expected = confirmations + 1
            click(session)
            try await wait { confirmations == expected }
            precondition(sourceApp.isActive && session.panel.isVisible)
        }

        try await catalog.focus(other)
        preferences.clickToFocus = false
        session.applyPreferences(preferences)
        let before = confirmations
        click(session)
        try await Task.sleep(for: .milliseconds(150))
        precondition(confirmations == before && otherApp.isActive, "Disabled single-click focus must preserve the foreground app.")
        preferences.clickToFocus = true
        session.applyPreferences(preferences)

        let target = focusedWindow(sourceApp)
        precondition(AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success)
        precondition(sourceApp.hide())
        try await wait { sourceApp.isHidden }
        click(session)
        try await wait { confirmations == before + 1 }
        precondition(sourceApp.isActive && focusedTitle(sourceApp) == source.title, "A minimized or hidden source must be restored.")

        let placement = SourceWindowPlacement()
        defer { placement.shutdown() }
        let original = try SourceWindowPlacement.frame(target)
        placement.onParked = { _, parked in session.sourceParked = parked }
        session.onPark = {
            do { try placement.park(source) } catch { fatalError("Parking failed: \(error)") }
        }
        session.onFocus = { window in
            try placement.restore(window.windowID)
            try await catalog.focus(window)
            confirmations += 1
        }
        session.onClose = { value in
            do { try placement.restore(value.source.windowID) } catch { fatalError("Restoration failed: \(error)") }
        }
        preferences.moveSourceOffscreen = true; session.applyPreferences(preferences)
        try placement.park(source)
        precondition(placement.isParked(source.windowID) && session.sourceParked)
        let expected = confirmations + 1
        click(session)
        try await wait { confirmations == expected }
        precondition(!placement.isParked(source.windowID))
        let restored = try SourceWindowPlacement.frame(target)
        precondition(restored.origin == original.origin)
        click(session)
        precondition(placement.isParked(source.windowID), "The next click must put the recalled source away.")
        try placement.restore(source.windowID)

        let crashing = Process()
        crashing.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        crashing.arguments = ["--park-and-crash", String(source.windowID)]
        try crashing.run()
        try await wait { !crashing.isRunning }
        precondition(crashing.terminationReason == .uncaughtSignal && crashing.terminationStatus == SIGKILL)
        try await wait { (try? SourceWindowPlacement.frame(target).origin) == original.origin }

        try await catalog.focus(other)
        click(session)
        click(session, count: 2)
        try await wait { !session.panel.isVisible }
        precondition(sourceApp.isActive && focusedTitle(sourceApp) == source.title,
                     "Double-click may close the panel only after source focus is confirmed.")

        var button: CFTypeRef?
        precondition(AXUIElementCopyAttributeValue(target, kAXCloseButtonAttribute as CFString, &button) == .success)
        guard let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { fatalError("Missing fixture close button.") }
        precondition(AXUIElementPerformAction(unsafeBitCast(button, to: AXUIElement.self), kAXPressAction as CFString) == .success)
        try await Task.sleep(for: .milliseconds(100))
        var rejected = false
        do { try await catalog.focus(source) } catch { rejected = true }
        precondition(rejected, "A closed source window must not be reported as focused.")
    }

    @MainActor private static func click(_ session: CaptureSession, count: Int = 1, point: NSPoint? = nil) {
        let surface = session.surface
        let point = point ?? NSPoint(x: surface.bounds.midX, y: surface.bounds.midY)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: surface.convert(point, to: nil), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: session.panel.windowNumber,
                               context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        }
        NSApp.postEvent(event(.leftMouseUp), atStart: true)
        NSApp.sendEvent(event(.leftMouseDown))
    }

    @MainActor private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for the real source window.")
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor private static func focusedWindow(_ app: NSRunningApplication) -> AXUIElement {
        var result: CFTypeRef?
        precondition(AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                                   kAXFocusedWindowAttribute as CFString, &result) == .success)
        guard let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { fatalError("Missing focused fixture window.") }
        return unsafeBitCast(result, to: AXUIElement.self)
    }

    @MainActor private static func focusedTitle(_ app: NSRunningApplication) -> String? {
        var result: CFTypeRef?
        precondition(AXUIElementCopyAttributeValue(focusedWindow(app), kAXTitleAttribute as CFString, &result) == .success)
        return result as? String
    }
}
