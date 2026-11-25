import AppKit
import ApplicationServices
import ScreenCaptureKit
import IceCore
import Darwin

@main
enum SourceFocusChecks {
    @MainActor private final class FixtureWindows: NSObject, NSWindowDelegate {
        var windows: [NSWindow] = []

        func windowWillClose(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else {
                preconditionFailure("Window close notification must identify its window.")
            }
            windows.removeAll { $0 === window }
        }
    }

    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--fixture" {
            app.setActivationPolicy(.regular)
            app.finishLaunching()
            let fixture = FixtureWindows()
            for index in 1...2 {
                let window = NSWindow(contentRect: NSRect(x: 160 + index * 60, y: 180, width: 420, height: 280),
                                      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.title = "IceScreen focus check \(index)"
                window.isReleasedWhenClosed = false
                window.delegate = fixture
                fixture.windows.append(window)
                window.collectionBehavior = [.fullScreenPrimary]
                let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
                text.string = "IceScreen source focus document \(index)"
                text.autoresizingMask = [.width, .height]
                window.contentView = text
                window.makeFirstResponder(text)
                window.makeKeyAndOrderFront(nil)
            }
            withExtendedLifetime(fixture) { app.run() }
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
                let suite = "org.icescreen.tests.source-focus.\(UUID().uuidString)"
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let settings = SettingsStore(defaults: defaults)
                if arguments[3] == "terminal" {
                    try await checkTerminalFullScreen(in: URL(fileURLWithPath: arguments[0]), settings: settings)
                } else {
                    try await check(in: URL(fileURLWithPath: arguments[0]), settings: settings, defaults: defaults)
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

    @MainActor private static func check(in directory: URL, settings: SettingsStore, defaults: UserDefaults) async throws {
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
        // ScreenCaptureKit also lists windows on inactive Spaces, where AXWindows can be empty.
        if try !WindowActivation.isOnVisibleSpace(source.windowID) {
            NativeFocusDiagnostics.step("bring_fixture_desktop_forward")
            try WindowActivation.bringForward(processID: sourceApp.processIdentifier, windowID: source.windowID)
        }
        try await wait("confirm_fixture_desktop") {
            try [source, other, sibling].allSatisfy {
                try WindowActivation.isOnVisibleSpace($0.windowID) && isOnScreen($0.windowID)
            }
        }
        let capturedTarget = try await readyElement(source)
        _ = try await readyElement(other)
        _ = try await readyElement(sibling)
        var preferences = settings.value
        let original = try await readableFrame(capturedTarget)
        let originalSpaces = try WindowActivation.spaceIDs(for: source.windowID)
        try require(!originalSpaces.isEmpty, "The captured fixture must have an actual Space identity.")
        let session = CaptureSession(source: source, viewport: .full, settings: settings, offset: 0)
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
            try await catalog.focus(window)
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
        session.resetZoom()

        try checkScrollZoom(session, foreground: otherApp)
        try await checkAutoHideOpacity(session, settings: settings, defaults: defaults, sibling: sibling, foreground: otherApp)

        try click(session, point: NSPoint(x: 24, y: session.surface.bounds.height - 24))
        print("Checking captured fixture return: PID=\(sourceApp.processIdentifier), window=\(source.windowID).")
        try await wait("click_delivery") { requests == 1 }
        try await wait("focus_confirmation") { confirmations == 1 }
        try await verifyRestored(source, application: sourceApp, target: capturedTarget,
                                 frame: original, spaces: originalSpaces, session: session)

        for _ in 0..<3 {
            NativeFocusDiagnostics.step("click_back_to_other")
            let back = confirmations + 1
            try click(session)
            try await wait("confirm_exact_previous_window") {
                try confirmations == back && otherApp.isActive
                    && WindowActivation.windowID(of: focusedWindow(otherApp)) == other.windowID
                    && session.panel.isVisible && !session.panel.isKeyWindow
            }
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

        try await catalog.focus(sibling)
        for window in [source, sibling, source] {
            NativeFocusDiagnostics.begin("same_app_round_trip")
            let expected = confirmations + 1
            try click(session)
            try await wait("click_delivery") { requests == expected }
            try await wait("focus_confirmation") { confirmations == expected }
            try await wait("confirm_exact_sibling_or_source") {
                try sourceApp.isActive && WindowActivation.windowID(of: focusedWindow(sourceApp)) == window.windowID
                    && session.panel.isVisible && !session.panel.isKeyWindow
            }
        }

        print("Checking double-click with a previous window remembered.")
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
            guard let windows = try read(session.focusTarget.root, kAXWindowsAttribute) as? [AXUIElement],
                  let entries = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
                throw RequestError.message("Cannot read actual window lists while confirming fixture closure.")
            }
            let identifiers = try windows.compactMap { try WindowActivation.windowID(of: $0) }
            let visible = entries.contains {
                ($0[kCGWindowNumber as String] as? CGWindowID) == source.windowID
                    && $0[kCGWindowIsOnscreen as String] as? Bool == true
            }
            // WindowServer may retain the closed window's offscreen record and its Space.
            return closed && !identifiers.contains(source.windowID) && identifiers.contains(sibling.windowID)
                && !visible
        }
        var rejected = false
        NativeFocusDiagnostics.step("verify_closed_source_rejection")
        do { try await catalog.focus(source, retainedTarget: session.focusTarget) }
        catch {
            guard case RequestError.message(let message) = error,
                  message == L10n.text("来源窗口已经关闭。", "The source window has closed.") else { throw error }
            rejected = true
        }
        try require(rejected, "A closed source window must not be reported as focused.")
        try await checkSiblingRegions(source: sibling, settings: settings)
    }

    @MainActor private static func checkSiblingRegions(source: SCWindow, settings: SettingsStore) async throws {
        let previous = settings.value
        settings.value.multiWindow = true
        settings.value.mediaControls = false
        settings.value.detectionNotifications = false
        settings.value.detectionCommand = ""
        let model = ApplicationModel(settings: settings)
        defer { model.shutdown(); settings.value = previous }
        let left = Viewport(rect: CGRect(x: 0, y: 0, width: 0.4, height: 1))
        let right = Viewport(rect: CGRect(x: 0.6, y: 0, width: 0.4, height: 1))
        model.start(source, viewport: left, intent: .region)
        model.start(source, viewport: right, intent: .region)
        try require(model.sessions.count == 2, "Two selected regions must create two panels.")
        let a = model.sessions[0], b = model.sessions[1]
        try await wait("confirm_both_region_streams") { a.hasCapturedFrame && b.hasCapturedFrame }
        try checkDetectionThresholdPreferences(model)
        // Press twice in one main-actor turn, before window discovery can finish.
        model.hotkeys.onCapture?(true)
        try require(model.isSelectingRegion, "The first region shortcut must start a selection.")
        model.hotkeys.onCapture?(true)
        try require(!model.isSelectingRegion, "A second region shortcut must cancel pending preparation.")
        model.hotkeys.onCapture?(true)
        try await wait("confirm_region_shortcut_reopens") { model.selector.isPresented }
        model.hotkeys.onCapture?(true)
        try require(!model.isSelectingRegion && model.sessions.map(\.id) == [a.id, b.id],
                    "Cancelling the visible selector must not restart capture or change existing panels.")
        a.togglePaused()
        a.resetZoom()
        try require(a.paused && !b.paused && a.viewport == .full && b.viewport == right && a.menuTitle != b.menuTitle,
                    "Region panels must retain independent controls and distinct menu entries.")
        model.start(source, toggleExisting: true)
        try require(model.sessions.count == 3, "Resetting a region zoom must not turn it into a window capture.")
        model.start(source, toggleExisting: true)
        try require(model.sessions.map(\.id) == [a.id, b.id], "Window capture hotkey must leave both regions intact.")
        model.preview.show(b)
        a.close()
        try require(model.preview.sessionID == b.id && model.preview.isPresented && model.sessions.count == 1,
                    "Closing one region must not dismiss its sibling's preview.")
        b.close()
        try require(!model.preview.isPresented && model.sessions.isEmpty, "Closing the preview owner must dismiss its preview.")
    }

    @MainActor private static func checkDetectionThresholdPreferences(_ model: ApplicationModel) throws {
        NativeFocusDiagnostics.step("verify_panel_detection_threshold_preferences")
        let settings = model.settings
        let previous = settings.value
        defer { settings.value = previous }
        let a = model.sessions[0], b = model.sessions[1]
        a.idleSeconds = 60; a.changeSeconds = 120
        b.idleSeconds = 30; b.changeSeconds = 5
        func requireThresholds(_ idleA: Double, _ changeA: Double, _ idleB: Double, _ changeB: Double,
                               after action: String) throws {
            try require(a.idleSeconds == idleA && a.changeSeconds == changeA
                        && b.idleSeconds == idleB && b.changeSeconds == changeB,
                        "Panels must retain the expected independent detection thresholds after \(action).")
        }
        // Exercise the real resize completion and settings subscription used by all live panels.
        let size = a.panel.frame.size
        a.beginHandleResize()
        a.panel.setContentSize(NSSize(width: size.width * 0.9, height: size.height * 0.9))
        a.endHandleResize()
        try require(settings.value.preferredWidth == Double(a.panel.frame.width), "Resize must save the panel width.")
        try requireThresholds(60, 120, 30, 5, after: "resizing a panel")
        let unrelatedChanges: [(String, (inout Preferences) -> Void)] = [
            ("language", { $0.language = $0.language == .english ? .chinese : .english }),
            ("normal transparency", { $0.panelOpacity = 0.73 }),
            ("hidden transparency", { $0.autoHideOpacity = 0.28 }),
            ("corner radius", { $0.cornerRadius = 18 }),
            ("detection mode", { $0.idleDetection.toggle(); $0.changeDetection.toggle() }),
            ("sensitivity", { $0.sensitiveDetection.toggle() })
        ]
        for (name, update) in unrelatedChanges {
            update(&settings.value)
            try requireThresholds(60, 120, 30, 5, after: name)
        }
        model.setFPS(app: a.bundleID, fps: 15)
        try requireThresholds(60, 120, 30, 5, after: "changing app frame rate")
        settings.value.idleSeconds = previous.idleSeconds == 10 ? 20 : 10
        try requireThresholds(settings.value.idleSeconds, 120, settings.value.idleSeconds, 5,
                              after: "explicitly changing the global idle threshold")
        a.idleSeconds = 60; b.idleSeconds = 30
        settings.value.changeSeconds = previous.changeSeconds == 20 ? 10 : 20
        try requireThresholds(60, settings.value.changeSeconds, 30, settings.value.changeSeconds,
                              after: "explicitly changing the global change threshold")
        let fresh = CaptureSession(source: a.source, viewport: .full, settings: settings, offset: 2)
        defer { fresh.close() }
        try require(fresh.idleSeconds == settings.value.idleSeconds && fresh.changeSeconds == settings.value.changeSeconds,
                    "New panels must inherit the current global thresholds, not another panel's overrides.")
        print("Passed native per-panel threshold preservation, independent global updates, and new-panel defaults checks.")
    }

    @MainActor private static func checkTerminalFullScreen(in directory: URL, settings: SettingsStore) async throws {
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
        defer { if !video.isTerminated { video.terminate() } }
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
        let desktop = Set(try WindowActivation.visibleSpaceIDs())
        var scenarioFailure: Error?
        do {
            try await runTerminalRoundTrip(source: source, terminal: terminal, videoSource: videoSource,
                                           video: video, catalog: catalog, settings: settings)
        } catch {
            scenarioFailure = error
            NativeFocusDiagnostics.event("scenario_failure", details: ["message": String(describing: error)])
        }
        // Closing a full-screen fixture is asynchronous, including after a failed test.
        do {
            try await NativeFocusDiagnostics.restoringDesktop {
                video.terminate()
                try await wait("confirm_fullscreen_fixture_quit") { video.isTerminated }
                if try !WindowActivation.isOnVisibleSpace(source.windowID) {
                    try WindowActivation.bringForward(processID: terminal.processIdentifier, windowID: source.windowID)
                }
                try await wait("confirm_original_desktop") {
                    try Set(WindowActivation.visibleSpaceIDs()) == desktop
                        && WindowActivation.isOnVisibleSpace(source.windowID) && isOnScreen(source.windowID)
                }
            }
        } catch {
            if let scenarioFailure { throw RequestError.message("\(scenarioFailure); desktop cleanup: \(error)") }
            throw error
        }
        if let scenarioFailure { throw scenarioFailure }
    }

    @MainActor private static func runTerminalRoundTrip(source: SCWindow, terminal: NSRunningApplication,
                                                       videoSource: SCWindow, video: NSRunningApplication,
                                                       catalog: WindowCatalog, settings: SettingsStore) async throws {
        _ = try await readyElement(source)
        _ = try await readyElement(videoSource)
        print("Terminal target: PID=\(terminal.processIdentifier), window=\(source.windowID), title=\(source.title ?? "").")
        print("Full-screen target: PID=\(video.processIdentifier), window=\(videoSource.windowID), title=\(videoSource.title ?? "").")
        NativeFocusDiagnostics.step("prepare_terminal_foreground")
        try await catalog.focus(source)
        print("Focused the actual Terminal window before capture.")
        let session = CaptureSession(source: source, viewport: .full, settings: settings, offset: 0)
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
            try await catalog.focus(window)
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
        func fixtureHasFocus() throws -> Bool {
            try video.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == video.processIdentifier
                && WindowActivation.windowID(of: focusedWindow(video)) == videoSource.windowID
        }
        var requestedFixtureFocus = false
        try await wait("confirm_fullscreen_space") {
            let videoVisible = try WindowActivation.isOnVisibleSpace(videoSource.windowID)
            let sourceVisible = try WindowActivation.isOnVisibleSpace(source.windowID)
            guard try isFullScreen(videoElement), videoVisible, isOnScreen(videoSource.windowID),
                  !sourceVisible, !isOnScreen(source.windowID), session.panel.isOnActiveSpace,
                  isOnScreen(CGWindowID(session.panel.windowNumber)) else { return false }
            if try fixtureHasFocus() { return true }
            if !requestedFixtureFocus {
                requestedFixtureFocus = true
                NativeFocusDiagnostics.snapshot("recover_fullscreen_fixture_focus")
                try WindowActivation.bringForward(processID: video.processIdentifier, windowID: videoSource.windowID)
            }
            return false
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
        try require(fixtureHasFocus(), "The exact full-screen fixture must still be in front before the click.")
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
        try click(session)
        try await wait("confirm_return_to_fullscreen_space") {
            let videoVisible = try WindowActivation.isOnVisibleSpace(videoSource.windowID)
            let sourceVisible = try WindowActivation.isOnVisibleSpace(source.windowID)
            return try confirmations == 2 && video.isActive && isFullScreen(videoElement) && videoVisible
                && WindowActivation.windowID(of: focusedWindow(video)) == videoSource.windowID
                && !sourceVisible && !isOnScreen(source.windowID)
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
            let front = NSWorkspace.shared.frontmostApplication
            let active = application.isActive
            let hidden = application.isHidden
            @MainActor func readFocusedID() throws -> CGWindowID? { try WindowActivation.windowID(of: focusedWindow(application)) }
            // When a system app is in front, AX focus in the target app is diagnostic only.
            let focusedID = active && !hidden && front?.processIdentifier == application.processIdentifier
                ? try readFocusedID() : try? readFocusedID()
            let sample = RestoredFocusSample(frontmostPID: front?.processIdentifier, frontmostBundle: front?.bundleIdentifier,
                                             active: active, hidden: hidden, focusedWindowID: focusedID)
            switch sample.verdict(expectedPID: application.processIdentifier, windowID: source.windowID) {
            case let .pending(details): throw SourceFocusPending(operation: details)
            case let .wrongWindow(details): throw RequestError.message("Source returned to the wrong window: \(details)")
            case .confirmed: break
            }
            let currentFrame = try windowFrame(target)
            let minimized = try isMinimized(target)
            let currentSpaces = try WindowActivation.spaceIDs(for: source.windowID)
            let visibleSpace = try WindowActivation.isOnVisibleSpace(source.windowID)
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

    @MainActor private static func checkAutoHideOpacity(_ session: CaptureSession, settings: SettingsStore,
                                                      defaults: UserDefaults, sibling: SCWindow, foreground: NSRunningApplication) async throws {
        NativeFocusDiagnostics.step("background_auto_hide_opacity")
        let preferences = settings.value
        var appearance = preferences
        appearance.panelTransparency = 0.3
        appearance.autoHideTransparency = 0.72
        session.applyPreferences(appearance)
        let inside = CGPoint(x: session.panel.frame.midX, y: session.panel.frame.midY)
        let outside = CGPoint(x: session.panel.frame.minX - 20, y: session.panel.frame.minY - 20)
        let originalFrame = session.panel.frame
        defer {
            session.surface.frameView.onFirstFrameRendered = nil
            if session.paused { session.togglePaused() }
            settings.value.autoHide = preferences.autoHide
            session.applyPreferences(preferences)
        }
        func verify(_ opacity: Double, hidden: Bool) throws {
            try require(session.autoHidden == hidden && session.panel.ignoresMouseEvents == hidden,
                        "Auto-hide must retain mouse-through behavior at every opacity.")
            try require(abs(session.panel.alphaValue - opacity) < 0.001 && session.panel.frame == originalFrame,
                        "Auto-hide opacity must preserve panel size and position.")
            try require(!NSApp.isActive && !session.panel.isKeyWindow
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground.processIdentifier,
                        "Auto-hide appearance changes must preserve foreground focus.")
        }
        var rendered = false
        session.surface.frameView.onFirstFrameRendered = { rendered = true }
        // 使用双击触发修饰键调用的同一个会话动作。
        session.toggleAutoHide()
        try require(settings.value.autoHide && SettingsStore(defaults: defaults).value.autoHide,
                    "Toggling a panel must update the saved Appearance switch.")
        let second = CaptureSession(source: sibling, viewport: .full, settings: settings, offset: 1)
        defer { second.close() }
        @MainActor func hasCheckedAutoHide(_ panel: CaptureSession) -> Bool {
            panel.makeMenu().items.first { $0.action == #selector(CaptureSession.toggleAutoHide) }?.state == .on
        }
        try require(second.autoHide && hasCheckedAutoHide(second), "A new panel must inherit the shared setting.")
        session.pointerMoved(to: inside)
        try await wait("confirm_translucent_auto_hide") { rendered && abs(session.panel.alphaValue - 0.28) < 0.001 }
        try verify(0.28, hidden: true)

        appearance.panelTransparency = 0.4
        session.applyPreferences(appearance)
        try verify(0.28, hidden: true)
        appearance.autoHideTransparency = 1
        session.applyPreferences(appearance)
        try await wait("confirm_invisible_auto_hide") { session.panel.alphaValue == 0 }
        try verify(0, hidden: true)

        rendered = false
        session.surface.frameView.onFirstFrameRendered = { rendered = true }
        appearance.autoHideTransparency = 0.58
        session.applyPreferences(appearance)
        try await wait("confirm_capture_after_opacity_change") { rendered && abs(session.panel.alphaValue - 0.42) < 0.001 }
        try verify(0.42, hidden: true)
        session.togglePaused()
        appearance.autoHideTransparency = 0
        session.applyPreferences(appearance)
        try await wait("confirm_opaque_auto_hide") { session.panel.alphaValue == 1 }
        try require(session.paused, "Changing auto-hide opacity must preserve an explicit pause.")
        try verify(1, hidden: true)
        session.pointerMoved(to: outside)
        try await wait("confirm_opacity_after_pointer_exit") { abs(session.panel.alphaValue - 0.6) < 0.001 }
        try verify(0.6, hidden: false)
        session.togglePaused()
        session.pointerMoved(to: inside)
        session.toggleAutoHide()
        try require(!settings.value.autoHide && !second.autoHide && !hasCheckedAutoHide(second),
                    "Disabling auto-hide must also update existing panels and their menus.")
        try await wait("confirm_opacity_after_auto_hide_disabled") { abs(session.panel.alphaValue - 0.6) < 0.001 }
        try verify(0.6, hidden: false)
        for (transparency, expectedAlpha) in [(1.0, 0.0), (0.0, 1.0)] {
            appearance.panelTransparency = transparency
            session.applyPreferences(appearance)
            try verify(expectedAlpha, hidden: false)
        }
        settings.value.autoHide = true
        try require(session.autoHide && second.autoHide && hasCheckedAutoHide(session),
                    "The Appearance switch must update every panel.")
        settings.value.autoHide = false
        print("Passed native auto-hide opacity, live rendering, preference updates, pointer exit, and mouse-through checks.")
    }

    @MainActor private static func checkScrollZoom(_ session: CaptureSession, foreground: NSRunningApplication) throws {
        NativeFocusDiagnostics.step("background_scroll_zoom")
        let surface = session.surface
        surface.layoutSubtreeIfNeeded()
        let point = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: nil)
        guard let input = surface.target(atWindowPoint: point) as? PanelInput else {
            throw RequestError.message("Scroll checks must target the actual panel content control.")
        }
        let baseline = Viewport.initial(anchor: .center, factor: 4)
        let panelFrame = session.panel.frame
        defer { session.resetZoom() }
        for units: CGScrollEventUnit in [.pixel, .line] {
            for (delta, command) in [(Int32(3), true), (Int32(-3), true), (Int32(3), false)] {
                session.setViewport(baseline)
                guard let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1,
                                           wheel1: delta, wheel2: 0, wheel3: 0) else {
                    throw RequestError.message("Cannot create a native scroll event.")
                }
                cgEvent.flags = command ? .maskCommand : []
                guard let event = NSEvent(cgEvent: cgEvent) else {
                    throw RequestError.message("Cannot bridge the native scroll event to AppKit.")
                }
                try require(event.type == .scrollWheel && event.scrollingDeltaY != 0
                            && (event.scrollingDeltaY > 0) == (delta > 0)
                            && event.modifierFlags.contains(.command) == command,
                            "The native event must retain its scroll direction and modifier.")
                input.scrollWheel(with: event)
                if command {
                    try require(delta > 0 ? session.viewport.magnification > baseline.magnification
                                          : session.viewport.magnification < baseline.magnification,
                                "Command-scroll must zoom in for positive deltas and out for negative deltas.")
                } else {
                    try require(session.viewport.magnification == baseline.magnification && session.viewport != baseline,
                                "Scrolling without Command must pan the captured content.")
                }
                try require(session.panel.frame == panelFrame && !session.panel.isKeyWindow && !NSApp.isActive
                            && NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground.processIdentifier,
                            "Scroll interactions must preserve panel geometry and foreground application focus.")
            }
        }
        print("Passed native pixel and line Command-scroll zoom direction, plain-scroll panning, and background focus checks.")
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
