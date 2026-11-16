import AppKit
import ApplicationServices
import ScreenCaptureKit
import IceCore
import Darwin

@main
enum SourceFocusChecks {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--fixture" {
            app.setActivationPolicy(.regular)
            app.finishLaunching()
            let windows = (1...2).map { index -> NSWindow in
                let window = NSWindow(contentRect: NSRect(x: 160 + index * 60, y: 180, width: 420, height: 280),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.title = "IceScreen focus check \(index)"
                window.isReleasedWhenClosed = false
                window.collectionBehavior = [.fullScreenPrimary]
                window.makeKeyAndOrderFront(nil)
                return window
            }
            withExtendedLifetime(windows) { app.run() }
            return
        }
        precondition(arguments.count == 3, "Pass the fixture directory, completion file, and project directory.")
        precondition(FileManager.default.changeCurrentDirectoryPath(arguments[2]))
        precondition(AXIsProcessTrusted(), "Source focus checks require Accessibility permission for this test executable.")
        precondition(CGPreflightScreenCaptureAccess(), "Source focus checks require Screen Recording permission.")
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            do {
                try await check(in: URL(fileURLWithPath: arguments[0]))
                try await checkTerminalFullScreen(in: URL(fileURLWithPath: arguments[0]))
                print("Passed cross-process source focus, repeated clicks, double-click close, disabled clicks, and closed-source checks.")
                try "passed\n".write(toFile: arguments[1], atomically: true, encoding: .utf8)
                app.terminate(nil)
            } catch {
                fputs("Source focus check failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func check(in directory: URL) async throws {
        print("Checking cross-process focus and background floating-panel interactions.")
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
        let capturedTarget = try SourceWindowRecovery.element(pid: sourceApp.processIdentifier, id: source.windowID)
        let original = try SourceWindowRecovery.frame(capturedTarget)
        let session = CaptureSession(source: source, viewport: .full, preferences: preferences, offset: 0)
        defer { session.close() }
        var confirmations = 0
        session.onFocus = { window in
            try await catalog.focus(window, retainedTarget: session.focusTarget)
            confirmations += 1
            print("Confirmed fixture return \(confirmations).")
        }
        session.start()
        session.surface.layoutSubtreeIfNeeded()
        try await wait { session.hasCapturedFrame }
        let afterCapture = try SourceWindowRecovery.frame(capturedTarget)
        precondition(afterCapture == original, "Capturing must preserve the source window frame.")
        print("Focusing other fixture: PID=\(otherApp.processIdentifier), window=\(other.windowID).")
        try await catalog.focus(other)
        precondition(!NSApp.isActive && !session.panel.isKeyWindow, "The content click must originate in a background panel.")

        let pinchOrigin = session.panel.convertPoint(toScreen: session.surface.convert(
            CGPoint(x: session.surface.bounds.width * 0.3, y: session.surface.bounds.height * 0.7), to: nil))
        session.beginMagnification(at: pinchOrigin)
        session.changeMagnification(by: 0.2)
        session.changeMagnification(by: 0.3)
        precondition(abs(session.viewport.magnification - 1.5) < 0.000001)
        session.changeMagnification(by: -0.25)
        precondition(abs(session.viewport.magnification - 1.25) < 0.000001)
        session.endMagnification()
        let afterPinch = session.viewport
        session.changeMagnification(by: 1)
        precondition(session.viewport == afterPinch, "Ended gestures must ignore late magnification changes.")
        precondition(otherApp.isActive && !session.panel.isKeyWindow,
                     "Magnification must keep the foreground app and non-key panel unchanged.")
        session.beginMagnification(at: pinchOrigin)
        session.toggleHidden()
        session.changeMagnification(by: 1)
        precondition(session.viewport == afterPinch, "Hidden panels must cancel their active magnification.")
        session.toggleHidden()
        session.resetZoom()

        click(session, point: NSPoint(x: 24, y: session.surface.bounds.height - 24))
        print("Checking captured fixture return: PID=\(sourceApp.processIdentifier), window=\(source.windowID).")
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
        print("Checking minimized and hidden source restoration.")
        precondition(AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success)
        precondition(AXUIElementSetAttributeValue(session.focusTarget.root, kAXHiddenAttribute as CFString, kCFBooleanTrue) == .success,
                     "The real source application must accept the Accessibility hide request.")
        try await wait { sourceApp.isHidden }
        print("Source is actually hidden; clicking the floating panel to restore it.")
        click(session)
        try await wait { confirmations == before + 1 }
        precondition(sourceApp.isActive && focusedTitle(sourceApp) == source.title, "A minimized or hidden source must be restored.")

        for _ in 0..<3 {
            let expected = confirmations + 1
            click(session)
            try await wait { confirmations == expected }
            let current = try SourceWindowRecovery.frame(target)
            precondition(current == original && sourceApp.isActive && session.panel.isVisible,
                         "Repeated single clicks must keep the source frame and retain the panel.")
        }

        try await catalog.focus(other)
        print("Checking double-click source return and panel close.")
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
        do { try await catalog.focus(source, retainedTarget: session.focusTarget) }
        catch {
            guard case RequestError.message(let message) = error, message == "来源窗口已经关闭。" else { throw error }
            rejected = true
        }
        precondition(rejected, "A closed source window must not be reported as focused.")
    }

    @MainActor private static func checkTerminalFullScreen(in directory: URL) async throws {
        print("Checking actual Terminal return from a full-screen Space.")
        let terminalConfiguration = NSWorkspace.OpenConfiguration()
        terminalConfiguration.createsNewApplicationInstance = true
        let terminal = try await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: terminalConfiguration)
        defer { terminal.terminate() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--fixture"]
        configuration.createsNewApplicationInstance = true
        let video = try await NSWorkspace.shared.openApplication(at: directory.appendingPathComponent("Other.app"),
                                                                configuration: configuration)
        defer { video.terminate() }
        let catalog = WindowCatalog()
        var source: SCWindow?
        var videoSource: SCWindow?
        for _ in 0..<160 {
            await catalog.refresh()
            if let error = catalog.error { fatalError(error) }
            source = catalog.windows.first { $0.owningApplication?.processID == terminal.processIdentifier && $0.isOnScreen }
            videoSource = catalog.windows.first { $0.owningApplication?.processID == video.processIdentifier }
            if source != nil && videoSource != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let source, let videoSource else { fatalError("Terminal and full-screen fixture windows must exist.") }
        try await catalog.focus(source)
        var preferences = Preferences()
        preferences.autoHide = false
        preferences.clickToFocus = true
        let session = CaptureSession(source: source, viewport: .full, preferences: preferences, offset: 0)
        defer { session.close() }
        guard let target = session.focusTarget.retainedElement else {
            fatalError("The actual Terminal AX window must be retained before leaving its Space.")
        }
        let original = try SourceWindowRecovery.frame(target)
        let videoTarget = SourceWindowTarget(videoSource)
        guard let videoElement = videoTarget.retainedElement else { fatalError("Missing full-screen fixture AX window.") }
        var confirmations = 0
        session.onFocus = { window in
            try await catalog.focus(window, retainedTarget: session.focusTarget)
            confirmations += 1
        }
        session.start()
        try await wait { session.hasCapturedFrame }
        try await catalog.focus(videoSource, retainedTarget: videoTarget)
        precondition(AXUIElementSetAttributeValue(videoElement, "AXFullScreen" as CFString, kCFBooleanTrue) == .success,
                     "The native fixture must enter an actual full-screen Space.")
        try await wait { isFullScreen(videoElement) && video.isActive && !isOnScreen(source.windowID) }
        precondition(!NSApp.isActive && !session.panel.isKeyWindow, "Click must originate in a background floating panel.")
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(session.focusTarget.root, kAXWindowsAttribute as CFString, &value)
        let windows = value as? [AXUIElement] ?? []
        let listed = try windows.contains { try WindowActivation.windowID(of: $0) == source.windowID }
        precondition(!listed, "The test must reproduce Terminal's off-Space AX window omission.")
        print("Reproduced actual Terminal off-Space AX omission: status=\(status.rawValue), windows=\(windows.count).")
        click(session)
        try await wait { confirmations == 1 }
        precondition(terminal.isActive && isOnScreen(source.windowID) && session.panel.isVisible,
                     "A floating-panel click must return from full-screen content to the actual Terminal Space.")
        let focusedID = try WindowActivation.windowID(of: focusedWindow(terminal))
        precondition(focusedID == source.windowID,
                     "The captured Terminal window ID must have focus.")
        let afterReturn = try SourceWindowRecovery.frame(target)
        precondition(afterReturn == original && isFullScreen(videoElement),
                     "Returning to Terminal must preserve its frame and leave the video window full-screen.")
        try await catalog.focus(videoSource, retainedTarget: videoTarget)
        try await wait { video.isActive && !isOnScreen(source.windowID) }
        try await catalog.focus(source)
        precondition(terminal.isActive && isOnScreen(source.windowID) && isFullScreen(videoElement),
                     "Window-ID-first lookup must return across Spaces even without a retained AX element.")
        let afterUncachedReturn = try SourceWindowRecovery.frame(target)
        precondition(afterUncachedReturn == original, "Uncached focus must not move the source window.")
        print("Passed actual Terminal/full-screen Space return, retained and uncached AX lookup, exact window ID, and frame preservation checks.")
        precondition(AXUIElementSetAttributeValue(videoElement, "AXFullScreen" as CFString, kCFBooleanFalse) == .success)
        try await wait { !isFullScreen(videoElement) }
    }

    @MainActor private static func isFullScreen(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success && value as? Bool == true
    }

    @MainActor private static func isOnScreen(_ id: CGWindowID) -> Bool {
        let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
        return entries.first { ($0[kCGWindowNumber as String] as? CGWindowID) == id }?[kCGWindowIsOnscreen as String] as? Bool == true
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

    @MainActor private static func wait(file: StaticString = #file, line: UInt = #line, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for the real source window.", file: file, line: line)
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
