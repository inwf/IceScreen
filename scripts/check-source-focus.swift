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
                let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
                text.string = "IceScreen source focus document \(index)"
                text.autoresizingMask = [.width, .height]
                window.contentView = text
                window.makeFirstResponder(text)
                window.makeKeyAndOrderFront(nil)
                return window
            }
            withExtendedLifetime(windows) { app.run() }
            return
        }
        precondition(arguments.count == 4 && ["terminal", "interactions"].contains(arguments[3]),
                     "Pass the fixture directory, completion file, project directory, and scenario.")
        precondition(FileManager.default.changeCurrentDirectoryPath(arguments[2]))
        try! NativeFocusDiagnostics.configure(at: URL(fileURLWithPath: arguments[1] + ".jsonl"))
        NativeFocusDiagnostics.begin(arguments[3])
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            do {
                NativeFocusDiagnostics.step("verify_test_permissions")
                try require(AXIsProcessTrusted(), "Source focus checks require Accessibility permission for this test executable.")
                try require(CGPreflightScreenCaptureAccess(), "Source focus checks require Screen Recording permission.")
                if arguments[3] == "terminal" {
                    try await checkTerminalFullScreen(in: URL(fileURLWithPath: arguments[0]))
                } else {
                    try await check(in: URL(fileURLWithPath: arguments[0]))
                }
                NativeFocusDiagnostics.snapshot("passed")
                print("Passed source focus scenario: \(arguments[3]).")
                try "passed\n".write(toFile: arguments[1], atomically: true, encoding: .utf8)
                app.terminate(nil)
            } catch {
                NativeFocusDiagnostics.event("failure", details: ["message": String(describing: error)])
                NativeFocusDiagnostics.snapshot("failed")
                fputs("Source focus check failed during \(NativeFocusDiagnostics.stage): \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func check(in directory: URL) async throws {
        print("Checking cross-process focus and background floating-panel interactions.")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--fixture"]
        configuration.createsNewApplicationInstance = true
        let sourceApp = try await NSWorkspace.shared.openApplication(at: directory.appendingPathComponent("Source.app"),
                                                                     configuration: configuration)
        NativeFocusDiagnostics.track("source", application: sourceApp)
        defer { sourceApp.terminate() }
        let otherApp = try await NSWorkspace.shared.openApplication(at: directory.appendingPathComponent("Other.app"),
                                                                    configuration: configuration)
        NativeFocusDiagnostics.track("other", application: otherApp)
        defer { otherApp.terminate() }
        let catalog = WindowCatalog()
        var source: SCWindow?
        var other: SCWindow?
        var sibling: SCWindow?
        NativeFocusDiagnostics.step("discover_fixture_windows")
        for _ in 0..<160 {
            await catalog.refresh()
            if let error = catalog.error { throw RequestError.message(error) }
            source = catalog.windows.first { $0.owningApplication?.processID == sourceApp.processIdentifier
                && $0.title == "IceScreen focus check 1" }
            other = catalog.windows.first { $0.owningApplication?.processID == otherApp.processIdentifier
                && $0.title == "IceScreen focus check 1" }
            sibling = catalog.windows.first { $0.owningApplication?.processID == sourceApp.processIdentifier
                && $0.title == "IceScreen focus check 2" }
            if source != nil && other != nil && sibling != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let source, let other, let sibling else {
            NativeFocusDiagnostics.snapshot("fixture_discovery_failed")
            throw RequestError.message("All three fixture windows must appear in ScreenCaptureKit before capture.")
        }
        let capturedTarget = try await readyElement(source)
        _ = try await readyElement(other)
        _ = try await readyElement(sibling)
        var preferences = Preferences()
        preferences.autoHide = false
        preferences.clickToFocus = true
        let original = try await readableFrame(capturedTarget)
        let originalSpaces = try WindowActivation.spaceIDs(for: source.windowID)
        try require(!originalSpaces.isEmpty, "The captured fixture must have an actual Space identity.")
        let session = CaptureSession(source: source, viewport: .full, preferences: preferences, offset: 0)
        NativeFocusDiagnostics.track(session)
        defer {
            NativeFocusDiagnostics.snapshot("before_fixture_cleanup")
            session.close()
        }
        var confirmations = 0
        var requests = 0
        session.onFocus = { window in
            requests += 1
            NativeFocusDiagnostics.event("focus_callback_started", details: ["request": requests, "windowID": window.windowID])
            try await catalog.focus(window, retainedTarget: session.focusTarget)
            confirmations += 1
            NativeFocusDiagnostics.event("focus_callback_confirmed", details: ["confirmation": confirmations, "windowID": window.windowID])
            print("Confirmed fixture return \(confirmations).")
        }
        session.start()
        session.surface.layoutSubtreeIfNeeded()
        try await wait("capture_first_frame") { session.hasCapturedFrame }
        let afterCapture = try await readableFrame(capturedTarget)
        try require(afterCapture == original, "Capturing must preserve the source window frame.")
        print("Focusing other fixture: PID=\(otherApp.processIdentifier), window=\(other.windowID).")
        NativeFocusDiagnostics.step("prepare_other_foreground")
        try await catalog.focus(other)
        try require(!NSApp.isActive && !session.panel.isKeyWindow, "The content click must originate in a background panel.")

        NativeFocusDiagnostics.step("background_magnification")
        let pinchOrigin = session.panel.convertPoint(toScreen: session.surface.convert(
            CGPoint(x: session.surface.bounds.width * 0.3, y: session.surface.bounds.height * 0.7), to: nil))
        session.beginMagnification(at: pinchOrigin)
        session.changeMagnification(by: 0.2)
        session.changeMagnification(by: 0.3)
        try require(abs(session.viewport.magnification - 1.5) < 0.000001, "Magnification must accumulate gesture changes.")
        session.changeMagnification(by: -0.25)
        try require(abs(session.viewport.magnification - 1.25) < 0.000001, "Magnification must apply negative changes.")
        session.endMagnification()
        let afterPinch = session.viewport
        session.changeMagnification(by: 1)
        try require(session.viewport == afterPinch, "Ended gestures must ignore late magnification changes.")
        try require(otherApp.isActive && !session.panel.isKeyWindow,
                     "Magnification must keep the foreground app and non-key panel unchanged.")
        session.beginMagnification(at: pinchOrigin)
        session.toggleHidden()
        session.changeMagnification(by: 1)
        try require(session.viewport == afterPinch, "Hidden panels must cancel their active magnification.")
        session.toggleHidden()
        session.resetZoom()

        try click(session, point: NSPoint(x: 24, y: session.surface.bounds.height - 24))
        print("Checking captured fixture return: PID=\(sourceApp.processIdentifier), window=\(source.windowID).")
        try await wait("click_delivery") { requests == 1 }
        try await wait("focus_confirmation") { confirmations == 1 }
        try await verifyRestored(source, application: sourceApp, target: capturedTarget,
                                 frame: original, spaces: originalSpaces, session: session)

        for _ in 0..<3 {
            NativeFocusDiagnostics.step("prepare_other_foreground")
            try await catalog.focus(other)
            let expected = confirmations + 1
            try click(session)
            try await wait("click_delivery") { requests == expected }
            try await wait("focus_confirmation") { confirmations == expected }
            try await verifyRestored(source, application: sourceApp, target: capturedTarget,
                                     frame: original, spaces: originalSpaces, session: session)
        }

        try await catalog.focus(other)
        preferences.clickToFocus = false
        session.applyPreferences(preferences)
        let before = confirmations
        NativeFocusDiagnostics.begin("disabled_single_click")
        let requestsBefore = requests
        try click(session)
        try await Task.sleep(for: .milliseconds(150))
        try require(requests == requestsBefore && confirmations == before && otherApp.isActive,
                    "Disabled single-click focus must preserve the foreground app and must not request focus.")
        preferences.clickToFocus = true
        session.applyPreferences(preferences)

        let target = capturedTarget
        for (name, minimized, hidden) in [("minimized_restoration", true, false),
                                        ("hidden_restoration", false, true),
                                        ("minimized_hidden_restoration", true, true)] {
            NativeFocusDiagnostics.begin(name)
            print("Checking \(name) with the other source window holding the initial keyboard focus.")
            NativeFocusDiagnostics.step("prepare_sibling_foreground")
            try await catalog.focus(sibling)
            try await wait("verify_sibling_focus") {
                let siblingFocusedID = try WindowActivation.windowID(of: focusedWindow(sourceApp))
                try require(siblingFocusedID == sibling.windowID, "The sibling must hold keyboard focus before restoration setup.")
                return true
            }
            if minimized {
                try await wait("request_minimize") {
                    try set(target, kAXMinimizedAttribute, kCFBooleanTrue)
                    return true
                }
                try await wait("confirm_minimized") { try isMinimized(target) }
            }
            if hidden {
                try await wait("request_hide") {
                    try set(session.focusTarget.root, kAXHiddenAttribute, kCFBooleanTrue)
                    return true
                }
            }
            try await wait("confirm_restoration_preconditions") { try sourceApp.isHidden == hidden && isMinimized(target) == minimized }
            session.refreshSourceState()
            try require(session.panel.isVisible, "Geometry monitoring must retain a hidden or minimized source's panel.")
            NativeFocusDiagnostics.snapshot("source_restoration_requested")
            let expected = confirmations + 1
            try click(session)
            try await wait("click_delivery") { requests == expected }
            try await wait("focus_confirmation") { confirmations == expected }
            try await verifyRestored(source, application: sourceApp, target: target,
                                     frame: original, spaces: originalSpaces, session: session)
            NativeFocusDiagnostics.snapshot("source_restoration_confirmed")
        }

        for _ in 0..<3 {
            NativeFocusDiagnostics.begin("repeated_source_click")
            let expected = confirmations + 1
            try click(session)
            try await wait("click_delivery") { requests == expected }
            try await wait("focus_confirmation") { confirmations == expected }
            try await verifyRestored(source, application: sourceApp, target: target,
                                     frame: original, spaces: originalSpaces, session: session)
        }

        try await catalog.focus(other)
        print("Checking double-click source return and panel close.")
        NativeFocusDiagnostics.begin("double_click_close")
        let expected = confirmations + 1
        let requestsBeforeDoubleClick = requests
        try click(session)
        try click(session, count: 2)
        try await wait("double_click_delivery") { requests > requestsBeforeDoubleClick }
        try await wait("double_click_close") { !session.panel.isVisible }
        try require(confirmations >= expected && confirmations == requests, "Closing the panel requires every requested source focus to complete.")
        try await verifyRestored(source, application: sourceApp, target: target,
                                 frame: original, spaces: originalSpaces, session: session, panelVisible: false)

        NativeFocusDiagnostics.begin("closed_source_rejection")
        try await wait("request_source_close") {
            let button = try read(target, kAXCloseButtonAttribute)
            try require(CFGetTypeID(button) == AXUIElementGetTypeID(), "Missing fixture close button.")
            let element = unsafeBitCast(button, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(element, 0.25)
            let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
            NativeFocusDiagnostics.accessibility("perform", element: element, attribute: kAXPressAction, status: status)
            // 关闭动作只发送一次；响应超时时通过实际关闭状态确认结果。
            try require(status == .success || status == .cannotComplete, "Fixture close request failed: AX status \(status.rawValue).")
            return true
        }
        try await wait("confirm_source_closed") {
            var role: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(target, kAXRoleAttribute as CFString, &role)
            NativeFocusDiagnostics.accessibility("read", element: target, attribute: kAXRoleAttribute, status: status, value: role)
            if status == .cannotComplete { throw SourceFocusPending(operation: "Waiting for fixture close: AX status \(status.rawValue)") }
            try require(status == .success || status == .invalidUIElement, "Reading closed fixture failed: AX status \(status.rawValue).")
            let closed = status == .invalidUIElement
            let entries = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
            return closed && !entries.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == source.windowID }
        }
        var rejected = false
        NativeFocusDiagnostics.step("verify_closed_source_rejection")
        do { try await catalog.focus(source, retainedTarget: session.focusTarget) }
        catch {
            guard case RequestError.message(let message) = error, message == "来源窗口已经关闭。" else { throw error }
            rejected = true
        }
        try require(rejected, "A closed source window must not be reported as focused.")
    }

    @MainActor private static func checkTerminalFullScreen(in directory: URL) async throws {
        print("Checking actual Terminal return from a full-screen Space.")
        let terminalConfiguration = NSWorkspace.OpenConfiguration()
        terminalConfiguration.createsNewApplicationInstance = true
        let terminal = try await NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: terminalConfiguration)
        NativeFocusDiagnostics.track("terminal", application: terminal)
        defer { terminal.terminate() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--fixture"]
        configuration.createsNewApplicationInstance = true
        let video = try await NSWorkspace.shared.openApplication(at: directory.appendingPathComponent("Other.app"),
                                                                configuration: configuration)
        NativeFocusDiagnostics.track("fullscreen", application: video)
        defer { video.terminate() }
        let catalog = WindowCatalog()
        var source: SCWindow?
        var videoSource: SCWindow?
        NativeFocusDiagnostics.step("discover_terminal_and_fullscreen_windows")
        for _ in 0..<160 {
            await catalog.refresh()
            if let error = catalog.error { throw RequestError.message(error) }
            source = catalog.windows.first { $0.owningApplication?.processID == terminal.processIdentifier
                && $0.isOnScreen && $0.frame.width >= 200 && $0.frame.height >= 200 && $0.title?.isEmpty == false }
            videoSource = catalog.windows.first { $0.owningApplication?.processID == video.processIdentifier
                && $0.title == "IceScreen focus check 1" }
            if source != nil && videoSource != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let source, let videoSource else { throw RequestError.message("Terminal and full-screen fixture windows must exist.") }
        _ = try await readyElement(source)
        _ = try await readyElement(videoSource)
        print("Terminal target: PID=\(terminal.processIdentifier), window=\(source.windowID), title=\(source.title ?? "").")
        print("Full-screen target: PID=\(video.processIdentifier), window=\(videoSource.windowID), title=\(videoSource.title ?? "").")
        NativeFocusDiagnostics.step("prepare_terminal_foreground")
        try await catalog.focus(source)
        print("Focused the actual Terminal window before capture.")
        var preferences = Preferences()
        preferences.autoHide = false
        preferences.clickToFocus = true
        let session = CaptureSession(source: source, viewport: .full, preferences: preferences, offset: 0)
        NativeFocusDiagnostics.track(session)
        defer {
            NativeFocusDiagnostics.snapshot("before_fixture_cleanup")
            session.close()
        }
        guard let target = session.focusTarget.retainedElement else {
            throw RequestError.message("The actual Terminal AX window must be retained before leaving its Space.")
        }
        let original = try await readableFrame(target)
        let videoTarget = SourceWindowTarget(videoSource)
        var confirmations = 0
        var requests = 0
        session.onFocus = { window in
            requests += 1
            NativeFocusDiagnostics.event("focus_callback_started", details: ["request": requests, "windowID": window.windowID])
            try await catalog.focus(window, retainedTarget: session.focusTarget)
            confirmations += 1
            NativeFocusDiagnostics.event("focus_callback_confirmed", details: ["confirmation": confirmations, "windowID": window.windowID])
        }
        session.start()
        try await wait("capture_first_frame") { session.hasCapturedFrame }
        print("Captured the first actual Terminal frame; focusing the full-screen fixture.")
        NativeFocusDiagnostics.step("prepare_fullscreen_foreground")
        try await catalog.focus(videoSource, retainedTarget: videoTarget)
        print("Focused the exact full-screen fixture window.")
        guard let videoElement = videoTarget.retainedElement else { throw RequestError.message("Missing focused full-screen fixture AX window.") }
        NativeFocusDiagnostics.begin("enter_fullscreen_space")
        try await wait("request_fullscreen") {
            try set(videoElement, "AXFullScreen", kCFBooleanTrue)
            return true
        }
        try await wait("confirm_fullscreen_space") {
            let videoVisible = try WindowActivation.isOnVisibleSpace(videoSource.windowID)
            let sourceVisible = try WindowActivation.isOnVisibleSpace(source.windowID)
            return try isFullScreen(videoElement) && video.isActive && videoVisible && !sourceVisible
                && !isOnScreen(source.windowID) && session.panel.isOnActiveSpace
                && isOnScreen(CGWindowID(session.panel.windowNumber))
        }
        NativeFocusDiagnostics.begin("terminal_off_space")
        let originalSpaces = try WindowActivation.spaceIDs(for: source.windowID)
        try require(!originalSpaces.isEmpty, "Terminal must have an actual Space identity.")
        let beforeReturn = try WindowActivation.isOnVisibleSpace(source.windowID)
        try require(!beforeReturn, "Terminal must actually be on an inactive Space before the panel click.")
        session.refreshSourceState()
        try require(session.panel.isVisible && isOnScreen(CGWindowID(session.panel.windowNumber)),
                     "The floating panel must remain physically on screen while Terminal is in another Space.")
        try require(!NSApp.isActive && !session.panel.isKeyWindow, "Click must originate in a background floating panel.")
        try await wait("verify_off_space_ax_omission") {
            let value = try read(session.focusTarget.root, kAXWindowsAttribute)
            guard let windows = value as? [AXUIElement] else {
                throw RequestError.message("Terminal returned an invalid AXWindows value.")
            }
            let listed = try windows.contains { try WindowActivation.windowID(of: $0) == source.windowID }
            try require(!listed, "Test precondition unmet: Terminal still lists the off-Space source window.")
            NativeFocusDiagnostics.event("off_space_omission_confirmed", details: ["axWindowsStatus": 0, "count": windows.count])
            return true
        }
        NativeFocusDiagnostics.begin("retained_terminal_return")
        try click(session)
        try await wait("click_delivery") { requests == 1 }
        try await wait("focus_confirmation") { confirmations == 1 }
        try await verifyRestored(source, application: terminal, target: target,
                                 frame: original, spaces: originalSpaces, session: session)
        try await wait("verify_video_stays_fullscreen") {
            try require(isFullScreen(videoElement), "Returning to Terminal must leave the video window full-screen.")
            return true
        }
        NativeFocusDiagnostics.begin("return_to_fullscreen_space")
        try await catalog.focus(videoSource, retainedTarget: videoTarget)
        try await wait("confirm_return_to_fullscreen_space") {
            let videoVisible = try WindowActivation.isOnVisibleSpace(videoSource.windowID)
            let sourceVisible = try WindowActivation.isOnVisibleSpace(source.windowID)
            return try video.isActive && isFullScreen(videoElement) && videoVisible && !sourceVisible && !isOnScreen(source.windowID)
        }
        NativeFocusDiagnostics.begin("uncached_terminal_return")
        NativeFocusDiagnostics.step("uncached_focus_request")
        try await catalog.focus(source)
        try await verifyRestored(source, application: terminal, target: target,
                                 frame: original, spaces: originalSpaces, session: session)
        try await wait("verify_video_stays_fullscreen") {
            try require(isFullScreen(videoElement), "Uncached return must leave the video window full-screen.")
            return true
        }
        print("Passed actual Terminal/full-screen Space return, retained and uncached AX lookup, exact window ID, and frame preservation checks.")
        try await wait("request_exit_fullscreen") {
            try set(videoElement, "AXFullScreen", kCFBooleanFalse)
            return true
        }
        try await wait("confirm_exit_fullscreen") { try !isFullScreen(videoElement) }
    }

    @MainActor private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw RequestError.message(message) }
    }

    @MainActor private static func readyElement(_ source: SCWindow) async throws -> AXUIElement {
        guard let pid = source.owningApplication?.processID else {
            throw RequestError.message("Fixture window has no owning application.")
        }
        let root = AXUIElementCreateApplication(pid)
        var target: AXUIElement?
        try await wait("prepare_ax_window_\(source.windowID)") {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                throw RequestError.message("Fixture exited before Accessibility preparation completed.")
            }
            guard let windows = try read(root, kAXWindowsAttribute) as? [AXUIElement] else {
                throw RequestError.message("Fixture returned an invalid AXWindows value.")
            }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, 0.25)
                guard try WindowActivation.windowID(of: element) == source.windowID else { continue }
                var owner: pid_t = 0
                let status = AXUIElementGetPid(element, &owner)
                try require(status == .success && owner == pid, "Fixture AX window owner does not match its captured PID.")
                try require(read(element, kAXRoleAttribute) as? String == kAXWindowRole, "Fixture AX object is not a window.")
                _ = try isMinimized(element)
                _ = try windowFrame(element)
                target = element
                return true
            }
            return false
        }
        guard let target else { throw RequestError.message("Fixture Accessibility preparation produced no window.") }
        return target
    }

    @MainActor private static func windowFrame(_ element: AXUIElement) throws -> CGRect {
        let position = try read(element, kAXPositionAttribute)
        let size = try read(element, kAXSizeAttribute)
        try require(CFGetTypeID(position) == AXValueGetTypeID() && CFGetTypeID(size) == AXValueGetTypeID(),
                    "Fixture frame attributes must be actual AXValue objects.")
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        try require(AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
                    && AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions),
                    "Fixture frame attributes have invalid coordinate types.")
        return CGRect(origin: point, size: dimensions)
    }

    @MainActor private static func readableFrame(_ element: AXUIElement) async throws -> CGRect {
        var frame = CGRect.zero
        try await wait("read_source_frame") {
            frame = try windowFrame(element)
            return true
        }
        return frame
    }

    @MainActor private static func verifyRestored(_ source: SCWindow, application: NSRunningApplication,
                                                target: AXUIElement, frame: CGRect, spaces: [UInt64],
                                                session: CaptureSession, panelVisible: Bool = true) async throws {
        try await wait("verify_exact_source_state") {
            let focusedID = try WindowActivation.windowID(of: focusedWindow(application))
            let currentFrame = try windowFrame(target)
            let minimized = try isMinimized(target)
            let currentSpaces = try WindowActivation.spaceIDs(for: source.windowID)
            let visibleSpace = try WindowActivation.isOnVisibleSpace(source.windowID)
            try require(application.isActive && !application.isHidden
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
                        "Source focus completed without the expected foreground application.")
            try require(focusedID == source.windowID, "Source focus completed on window \(focusedID ?? 0); expected \(source.windowID).")
            try require(!minimized && isOnScreen(source.windowID) && visibleSpace,
                        "The exact source window must be restored and visible on the current Space.")
            try require(currentFrame == frame && Set(currentSpaces) == Set(spaces),
                        "Source restoration must preserve its original frame and Space identity.")
            try require(session.panel.isVisible == panelVisible && !session.panel.isKeyWindow,
                        "The panel must have the expected visibility and must not take keyboard focus.")
            if panelVisible {
                try require(isOnScreen(CGWindowID(session.panel.windowNumber)), "The retained panel must be physically on screen.")
            }
            return true
        }
    }

    @MainActor private static func isFullScreen(_ element: AXUIElement) throws -> Bool {
        let value = try read(element, "AXFullScreen")
        guard let value = value as? Bool else {
            throw RequestError.message("The fixture returned a non-Boolean AXFullScreen value.")
        }
        return value
    }

    @MainActor private static func isMinimized(_ element: AXUIElement) throws -> Bool {
        let value = try read(element, kAXMinimizedAttribute)
        guard let value = value as? Bool else {
            throw RequestError.message("The fixture returned a non-Boolean AXMinimized value.")
        }
        return value
    }

    @MainActor private static func read(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef {
        AXUIElementSetMessagingTimeout(element, 0.25)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        NativeFocusDiagnostics.accessibility("read", element: element, attribute: attribute, status: status, value: value)
        if status == .cannotComplete { throw SourceFocusPending(operation: "Fixture read \(attribute): AX status \(status.rawValue)") }
        guard status == .success, let value else {
            throw RequestError.message("Fixture read \(attribute) failed: AX status \(status.rawValue).")
        }
        return value
    }

    @MainActor private static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) throws {
        AXUIElementSetMessagingTimeout(element, 0.25)
        let status = AXUIElementSetAttributeValue(element, attribute as CFString, value)
        NativeFocusDiagnostics.accessibility("set", element: element, attribute: attribute, status: status, value: value)
        if status == .cannotComplete { throw SourceFocusPending(operation: "Fixture set \(attribute): AX status \(status.rawValue)") }
        guard status == .success else {
            throw RequestError.message("Fixture set \(attribute) failed: AX status \(status.rawValue).")
        }
    }

    @MainActor private static func isOnScreen(_ id: CGWindowID) -> Bool {
        let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return entries.first { ($0[kCGWindowNumber as String] as? CGWindowID) == id }?[kCGWindowIsOnscreen as String] as? Bool == true
    }

    @MainActor private static func click(_ session: CaptureSession, count: Int = 1, point: NSPoint? = nil) throws {
        NativeFocusDiagnostics.step("dispatch_panel_click")
        try require(session.panel.isVisible && !session.panel.ignoresMouseEvents, "The test panel must accept input before dispatch.")
        let surface = session.surface
        surface.layoutSubtreeIfNeeded()
        let point = point ?? NSPoint(x: surface.bounds.midX, y: surface.bounds.midY)
        let hit = surface.target(atWindowPoint: surface.convert(point, to: nil))
        try require(hit is PanelInput, "The test click must hit the real content control; actual target: \(String(describing: hit)).")
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: surface.convert(point, to: nil), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: session.panel.windowNumber,
                               context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        }
        NSApp.postEvent(event(.leftMouseUp), atStart: true)
        NSApp.sendEvent(event(.leftMouseDown))
        NativeFocusDiagnostics.event("appkit_click_dispatched", details: ["windowID": session.panel.windowNumber, "clickCount": count])
    }

    @MainActor private static func wait(_ stage: String, file: StaticString = #file, line: UInt = #line,
                                       _ condition: () throws -> Bool) async throws {
        NativeFocusDiagnostics.step(stage)
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        var nextSnapshot = ContinuousClock.now.advanced(by: .seconds(1))
        var pendingOperation = ""
        while true {
            try Task.checkCancellation()
            if let failure = NativeFocusDiagnostics.captureFailure { throw RequestError.message(failure) }
            guard ContinuousClock.now < deadline else {
                NativeFocusDiagnostics.snapshot("timeout", file: file, line: line)
                throw RequestError.message("Timed out during \(stage) at \(file):\(line). \(pendingOperation)")
            }
            do {
                let ready = try condition()
                if let failure = NativeFocusDiagnostics.captureFailure { throw RequestError.message(failure) }
                if ready && ContinuousClock.now < deadline {
                    NativeFocusDiagnostics.event("stage_passed")
                    return
                }
                pendingOperation = ""
            } catch let pending as SourceFocusPending {
                pendingOperation = pending.operation
            }
            if ContinuousClock.now >= nextSnapshot {
                NativeFocusDiagnostics.snapshot("waiting", file: file, line: line)
                nextSnapshot = ContinuousClock.now.advanced(by: .seconds(1))
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor private static func focusedWindow(_ app: NSRunningApplication) throws -> AXUIElement {
        let result = try read(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute)
        guard CFGetTypeID(result) == AXUIElementGetTypeID() else { throw RequestError.message("Missing focused fixture window.") }
        return unsafeBitCast(result, to: AXUIElement.self)
    }

}
