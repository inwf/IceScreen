import AppKit
import CoreVideo
import QuartzCore
import IceCore
import ImageIO
import UniformTypeIdentifiers
import Darwin
import Combine

@main
enum PanelEventChecks {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let application = NSApplication.shared
        if CommandLine.arguments.dropFirst().first == "--foreground-fixture" {
            runForegroundFixture(application)
            return
        }
        precondition(CommandLine.arguments.count == 4, "Pass the foreground application path, completion file, and project directory.")
        precondition(FileManager.default.changeCurrentDirectoryPath(CommandLine.arguments[3]),
                     "The native checks require the project working directory.")
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        guard let screen = NSScreen.main else { fatalError("Panel checks require an active macOS graphical session.") }
        checkBackgroundPanels(application, screen: screen)
        application.activate(ignoringOtherApps: true)
        let frame = NSRect(x: screen.visibleFrame.midX - 90, y: screen.visibleFrame.midY - 70, width: 180, height: 140)
        let lower = makePanel(frame)
        let upper = makePanel(frame.offsetBy(dx: 20, dy: 20))
        defer { lower.close(); upper.close() }
        let point = NSPoint(x: frame.midX, y: frame.midY)
        let panels = [lower, upper]

        lower.orderFrontRegardless()
        upper.orderFrontRegardless()
        settle()
        let hitWindowNumber = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        let panelState = panels.map {
            "number=\($0.windowNumber), visible=\($0.isVisible), activeSpace=\($0.isOnActiveSpace), ignoresMouse=\($0.ignoresMouseEvents), frame=\($0.frame)"
        }.joined(separator: "; ")
        let orderedWindows = NSApp.orderedWindows.map { String($0.windowNumber) }.joined(separator: ",")
        precondition(PanelHitTesting.frontmost(at: point, among: panels) === upper,
                     "Visible NSPanel must receive hover actions. hit=\(hitWindowNumber), panels=[\(panelState)], ordered=[\(orderedWindows)]")
        lower.orderFrontRegardless()
        settle()
        precondition(PanelHitTesting.frontmost(at: point, among: panels) === lower, "Hover actions must follow actual window ordering.")
        lower.ignoresMouseEvents = true
        settle()
        precondition(PanelHitTesting.frontmost(at: point, among: panels) === upper, "Mouse-through panels must not swallow regular hover actions.")
        upper.orderOut(nil)
        settle()
        precondition(PanelHitTesting.frontmost(at: point, among: panels) == nil, "Hidden panels must not receive regular hover actions.")
        lower.ignoresMouseEvents = false
        settle()
        precondition(PanelHitTesting.frontmost(at: NSPoint(x: frame.minX - 20, y: frame.minY - 20), among: panels) == nil,
                     "Typing outside a panel must remain unaffected.")
        checkSurface(in: lower)
        checkCaptureDetection()
        checkPreviewTransition(in: screen.visibleFrame)
        checkAppearancePreview(in: screen.visibleFrame)
        checkLanguageSettings()
        print("Passed 5 native NSPanel hit-testing checks.")
        try! "passed\n".write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
    }

    @MainActor private static func runForegroundFixture(_ application: NSApplication) {
        application.setActivationPolicy(.regular)
        application.finishLaunching()
        guard let screen = NSScreen.main else { fatalError("The foreground fixture requires WindowServer.") }
        let window = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX - 260, y: screen.visibleFrame.midY - 180,
                                                 width: 520, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "IceScreen foreground input checks"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        withExtendedLifetime(window) { application.run() }
    }

    @MainActor private static func wait(_ message: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            precondition(Date() < deadline, message)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    @MainActor private static func checkBackgroundPanels(_ application: NSApplication, screen: NSScreen) {
        var foreground: NSRunningApplication?
        var launchError: Error?
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--foreground-fixture"]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: CommandLine.arguments[1]), configuration: configuration) { app, error in
            DispatchQueue.main.async { foreground = app; launchError = error }
        }
        wait("The foreground fixture did not launch.") { foreground != nil || launchError != nil }
        if let launchError { fatalError("Foreground fixture launch failed: \(launchError)") }
        guard let foreground else { fatalError("Missing foreground fixture process.") }
        defer {
            precondition(foreground.terminate(), "The foreground fixture must terminate after checks.")
            wait("The foreground fixture did not exit.") { foreground.isTerminated }
        }
        let pid = foreground.processIdentifier
        wait("The independent fixture must own foreground focus.") {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && !application.isActive
        }
        let frame = NSRect(x: screen.visibleFrame.midX - 180, y: screen.visibleFrame.midY - 120, width: 360, height: 240)
        let lower = makePanel(frame)
        let upper = makePanel(frame.offsetBy(dx: 20, dy: 20))
        defer { lower.close(); upper.close() }
        let panels = [lower, upper]
        func assertBackground() {
            precondition(!application.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                         "Background panel interaction must preserve the independent foreground process.")
            precondition(panels.allSatisfy { !$0.isKeyWindow && !$0.isMainWindow },
                         "Background panels must stay non-key and non-main.")
        }
        let point = NSPoint(x: frame.midX, y: frame.midY)
        lower.orderFrontRegardless()
        upper.orderFrontRegardless()
        wait("WindowServer must target the upper background panel.") {
            PanelHitTesting.frontmost(at: point, among: panels) === upper
        }
        assertBackground()
        lower.orderFrontRegardless()
        wait("Background hit testing must follow WindowServer ordering.") {
            PanelHitTesting.frontmost(at: point, among: panels) === lower
        }
        assertBackground()
        lower.ignoresMouseEvents = true
        settle()
        precondition(PanelHitTesting.frontmost(at: point, among: panels) === upper,
                     "A mouse-through background panel must not consume the hit target.")
        upper.orderOut(nil)
        settle()
        precondition(PanelHitTesting.frontmost(at: point, among: panels) == nil,
                     "Hidden and mouse-through background panels must not receive hover actions.")
        assertBackground()
        lower.ignoresMouseEvents = false
        let surface = PanelSurface(frame: NSRect(origin: .zero, size: frame.size))
        lower.contentView = surface
        surface.layoutSubtreeIfNeeded()
        var clicks = 0
        surface.onContentClick = { clicks += 1 }
        for hovered in [false, true] {
            surface.setHovered(hovered)
            surface.layoutSubtreeIfNeeded()
            let local = surface.convert(NSPoint(x: 180, y: 120), to: nil)
            precondition(surface.target(atWindowPoint: local) is PanelInput,
                         "Background content must target the real PanelInput.")
            func event(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: local, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: lower.windowNumber, context: nil, eventNumber: 0,
                                   clickCount: 1, pressure: 1)!
            }
            let before = clicks
            assertBackground()
            // 通过真实 AppKit 分发和事件跟踪检查点击；硬件输入另行验收。
            application.postEvent(event(.leftMouseUp), atStart: true)
            application.sendEvent(event(.leftMouseDown))
            precondition(clicks == before + 1, "A background first click must dispatch exactly once.")
            settle()
            assertBackground()
        }
        let outside = NSPoint(x: frame.minX - 30, y: frame.midY)
        precondition(PanelHitTesting.frontmost(at: outside, among: panels) == nil,
                     "Input outside background panels must not target them.")
        checkHintPlacement(in: lower, assertBackground: assertBackground)
        lower.orderOut(nil)
        settle()
        precondition(PanelHitTesting.frontmost(at: point, among: panels) == nil,
                     "Closing all background panels must release the WindowServer target.")
        assertBackground()
        print("Passed background WindowServer ordering, mouse-through, hiding, AppKit first-click dispatch, and foreground PID preservation checks.")
    }

    @MainActor private static func accessibilityElement(_ object: Any, identifier: String, depth: Int = 0) -> (any NSAccessibilityProtocol)? {
        guard depth < 20, let element = object as? any NSAccessibilityProtocol else { return nil }
        if element.accessibilityIdentifier() == identifier { return element }
        for child in element.accessibilityChildren() ?? [] {
            if let result = accessibilityElement(child, identifier: identifier, depth: depth + 1) { return result }
        }
        return nil
    }

    @MainActor private static func checkHintPlacement(in source: FloatingPanel, assertBackground: () -> Void) {
        let presenter = PanelHintPresenter()
        let original = source.frame
        defer { presenter.close(); source.alphaValue = 1; source.setFrame(original, display: true) }
        func checkCentered() {
            guard let hint = presenter.panel, let host = hint.contentView else { fatalError("Missing hint window.") }
            host.layoutSubtreeIfNeeded()
            precondition(hint.frame == source.contentRect(forFrameRect: source.frame), "Hint host must follow the source content frame.")
            precondition(host.frame.size == hint.frame.size && !host.isOpaque, "The transparent hosting view must fill its window.")
            precondition(hint.ignoresMouseEvents && !hint.canBecomeKey && !hint.isKeyWindow && !hint.isMainWindow,
                         "Hints must remain mouse-through and nonactivating.")
            precondition(PanelHitTesting.frontmost(at: NSPoint(x: source.frame.midX, y: source.frame.midY), among: [source]) === source,
                         "The hint must leave WindowServer hit testing on its source.")
            wait("The actual hint accessibility element must be available.") {
                accessibilityElement(host, identifier: "panel.hint") != nil
            }
            let rendered = accessibilityElement(host, identifier: "panel.hint")!.accessibilityFrame()
            precondition(abs(rendered.midX - source.frame.midX) < 2 && abs(rendered.midY - source.frame.midY) < 2,
                         "The rendered hint must be centered over its source: \(rendered), source: \(source.frame).")
            precondition(source.frame.insetBy(dx: -1, dy: -1).contains(rendered), "The rendered hint must fit inside the source.")
            assertBackground()
        }
        for message in ["自动隐藏已开启", "自动隐藏已关闭", "Auto-hide enabled", "Auto-hide disabled",
                        "无法调整来源进度，请检查系统设置中的自动化权限。", "Unable to seek in the source. Check Automation permission in System Settings."] {
            presenter.show(message, over: source)
            settle()
            checkCentered()
        }
        let existing = presenter.panel!
        for size in [NSSize(width: 180, height: 140), NSSize(width: 80, height: 40), NSSize(width: 440, height: 280)] {
            source.setFrame(NSRect(x: original.minX + 24, y: original.minY + 16, width: size.width, height: size.height), display: true)
            settle()
            precondition(presenter.panel === existing, "Moving and resizing must update the existing hint.")
            checkCentered()
        }
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            for origin in [visible.origin, CGPoint(x: visible.maxX - source.frame.width, y: visible.maxY - source.frame.height)] {
                source.setFrameOrigin(origin)
                settle()
                checkCentered()
            }
        }
        source.alphaValue = 0
        precondition(existing.isVisible && existing.alphaValue > 0, "Auto-hiding the source must keep its hint readable.")
        presenter.show("替换提示", over: source)
        precondition(!existing.isVisible && presenter.panel !== existing, "A replacement must dismiss the previous hint.")
        presenter.close()
        precondition(presenter.panel == nil)
        let closing = makePanel(original)
        closing.orderFrontRegardless()
        presenter.show("Auto-hide enabled", over: closing)
        let orphan = presenter.panel!
        closing.close()
        precondition(presenter.panel == nil && !orphan.isVisible, "Closing the source must dismiss its hint immediately.")
        print("Passed native bilingual hint centering, movement, resizing, replacement, and input isolation checks.")
    }

    @MainActor private static func checkLanguageSettings() {
        let previousLanguage = L10n.language
        let suite = "org.icescreen.tests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            L10n.language = previousLanguage
        }
        defaults.set(Data(#"{"panelOpacity":0.73,"autoHideOpacity":0.28}"#.utf8), forKey: "IceScreen.preferences.v1")
        let store = SettingsStore(defaults: defaults)
        precondition(store.value.language == .chinese && L10n.language == .chinese)
        let surface = PanelSurface(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        surface.setHovered(true)
        let chrome = surface.subviews.compactMap { $0 as? PanelChromeHost }.first!
        let resize = surface.subviews.compactMap { $0 as? PanelResizeHandle }.first!
        let subscription = store.$value.sink { preferences in
            precondition(L10n.language == preferences.language, "Published settings must already use the selected language.")
            surface.applyAppearance(preferences, enhanced: false)
        }
        defer { subscription.cancel() }
        let regions = chrome.state.regions(in: surface.bounds.size).map(\.frame)
        for language in [AppLanguage.english, .chinese, .english] {
            store.value.language = language
            precondition(chrome.state.value.language == language, "Existing panel chrome must update language immediately.")
            precondition(chrome.state.regions(in: surface.bounds.size).map(\.frame) == regions,
                         "Language changes must preserve control targeting geometry.")
            precondition(chrome.state.detectionTitle == (language == .english ? "Disabled" : "未启用"))
            precondition(resize.toolTip == (language == .english ? "Drag to resize panel" : "拖动调整浮窗大小"))
            precondition(PanelAction.close.label == (language == .english ? "Close panel" : "关闭浮窗"))
            precondition(SettingsStore(defaults: defaults).value.language == language, "Language must survive reloading saved preferences.")
            precondition(store.value.panelOpacity == 0.73 && store.value.autoHideOpacity == 0.28)
        }
        precondition(AppearanceSample.image(dark: false, language: .english) !== AppearanceSample.image(dark: false, language: .chinese),
                     "The built-in preview must retain separate samples for each language.")
        print("Passed native language persistence, live panel translation, and control geometry checks.")
    }

    @MainActor private static func checkAppearancePreview(in screen: NSRect) {
        let window = NSWindow(contentRect: NSRect(x: screen.midX - 220, y: screen.midY - 110, width: 440, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let preview = AppearancePreviewView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        window.contentView = preview
        window.orderFrontRegardless()
        defer { preview.releasePreview(); window.close() }
        var preferences = Preferences()
        preferences.cornerRadius = 30
        preferences.panelOpacity = 0.4
        preferences.enhanceContrast = true
        preferences.contrastStrength = 0.37
        preferences.sharpnessStrength = 0.81
        preferences.hoverBlur = 0.8
        var rendered = false
        preview.surface.frameView.onFirstFrameRendered = { rendered = true }
        preview.update(preferences, original: false, dark: false)
        preview.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(3)
        while !rendered {
            precondition(preview.surface.frameView.renderFailure == nil, preview.surface.frameView.renderingState)
            precondition(Date() < deadline, "Appearance sample must render through the real Metal renderer. \(preview.surface.frameView.renderingState)")
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(preview.surface.layer!.cornerRadius == 30 && abs(preview.surface.alphaValue - 0.4) < 0.001)
        precondition(preview.surface.frameView.layer!.cornerRadius == 30 && preview.surface.frameView.layer!.masksToBounds,
                     "The preview image must retain the requested corner clipping.")
        precondition(preview.surface.frameView.enhanced && preview.surface.hoverBlur == 0.8)
        precondition(preview.surface.frameView.enhancement.contrast == 0.37 && preview.surface.frameView.enhancement.sharpness == 0.81)
        let contentPoint = preview.convert(CGPoint(x: preview.bounds.midX, y: preview.bounds.midY), to: preview.superview)
        precondition(preview.hitTest(contentPoint) === preview, "Preview content must not route to floating-window gestures.")
        precondition(!preview.mouseDownCanMoveWindow, "Preview content must not start dragging the settings window.")
        func hover(_ inside: Bool) {
            let event = NSEvent.enterExitEvent(with: inside ? .mouseEntered : .mouseExited,
                                              location: .zero, modifierFlags: [], timestamp: 0,
                                              windowNumber: window.windowNumber, context: nil,
                                              eventNumber: 0, trackingNumber: 0, userData: nil)!
            if inside { preview.mouseEntered(with: event) } else { preview.mouseExited(with: event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            precondition(preview.pointerInside == inside)
        }
        hover(true)
        let shade = preview.surface.subviews.compactMap { $0 as? PanelDimView }.first!
        precondition(!shade.isHidden, "Pointer entry must show the configured edge shade without a toggle.")
        preferences.dimOnHover = false
        preview.update(preferences, original: false, dark: false)
        precondition(shade.isHidden, "Disabling the shade while hovered must update the preview immediately.")
        preferences.autoHide = true
        preview.update(preferences, original: false, dark: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(preview.surface.alphaValue == 0, "Auto-hide must hide the entire sample under the pointer.")
        precondition(!preview.trackingAreas.isEmpty, "The stationary parent must retain hover tracking while the sample is invisible.")
        for opacity in [0.28, 1.0, 0.0, 0.15] {
            preferences.autoHideOpacity = opacity
            preview.update(preferences, original: false, dark: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            precondition(abs(preview.surface.alphaValue - opacity) < 0.001,
                         "Changing auto-hide opacity must immediately update the hovered preview.")
        }
        hover(false)
        precondition(abs(preview.surface.alphaValue - 0.4) < 0.001, "Pointer exit must restore the selected opacity.")
        preferences.autoHide = false
        preview.update(preferences, original: true, dark: false)
        precondition(!preview.surface.frameView.enhanced && preferences.enhanceContrast,
                     "Comparing the original must leave the actual preference enabled.")
        precondition(preview.surface.frameView.enhancement.contrast == 0.37 && preview.surface.frameView.enhancement.sharpness == 0.81,
                     "Original comparison must preserve both configured enhancement strengths.")
        preview.update(preferences, original: false, dark: true)
        precondition(preview.surface.frameView.enhanced)
        window.setContentSize(NSSize(width: 480, height: 220))
        preview.layoutSubtreeIfNeeded()
        precondition(preview.bounds.contains(preview.surface.frame), "Resizing must retain the full sample inside the preview.")
        checkImportedAppearance(in: preview, preferences: preferences)
        print("Passed native appearance rendering, pointer hover and hiding, image decoding, live settings, and input isolation checks.")
    }

    @MainActor private static func checkImportedAppearance(in preview: AppearancePreviewView, preferences: Preferences) {
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/tmp/appearance-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let png = folder.appendingPathComponent("sample.png")
            let context = CGContext(data: nil, width: 1600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.clear(CGRect(x: 0, y: 0, width: 1600, height: 800))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
            let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            precondition(CGImageDestinationFinalize(destination))
            let image = try AppearanceImage.load(from: png)
            precondition(CVPixelBufferGetWidth(image.pixels) == 1024 && CVPixelBufferGetHeight(image.pixels) == 512,
                         "Imported images must be downsampled without changing their aspect ratio.")
            CVPixelBufferLockBaseAddress(image.pixels, .readOnly)
            let bytes = CVPixelBufferGetBaseAddress(image.pixels)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(image.pixels) * 256
            precondition(bytes[row + 128 * 4 + 2] == 255 && bytes[row + 128 * 4 + 3] == 255)
            precondition(bytes[row + 900 * 4 + 3] == 0, "PNG alpha must survive decoding.")
            CVPixelBufferUnlockBaseAddress(image.pixels, .readOnly)
            var rendered = false
            preview.surface.frameView.onFirstFrameRendered = { rendered = true }
            preview.update(preferences, original: false, dark: false, image: image)
            preview.layoutSubtreeIfNeeded()
            let deadline = Date().addingTimeInterval(3)
            while !rendered {
                precondition(preview.surface.frameView.renderFailure == nil, preview.surface.frameView.renderingState)
                precondition(Date() < deadline, "An imported image must render through the real Metal path. \(preview.surface.frameView.renderingState)")
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            precondition(abs(preview.surface.frame.width / preview.surface.frame.height - 2) < 0.001)
            precondition(preview.surface.frameView.layer!.isOpaque == false)
            preview.update(preferences, original: false, dark: true, image: image)
            preview.layoutSubtreeIfNeeded()
            precondition(abs(preview.surface.frame.width / preview.surface.frame.height - 2) < 0.001,
                         "An appearance change must keep the imported image.")
            preview.update(preferences, original: false, dark: true)
            preview.layoutSubtreeIfNeeded()
            precondition(abs(preview.surface.frame.width / preview.surface.frame.height - 16.0 / 9) < 0.001,
                         "Restoring the example must restore its original aspect ratio.")
            let rotated = folder.appendingPathComponent("portrait.jpg")
            let jpeg = CGImageDestinationCreateWithURL(rotated as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(jpeg, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
            precondition(CGImageDestinationFinalize(jpeg))
            let portrait = try AppearanceImage.load(from: rotated)
            precondition(CVPixelBufferGetWidth(portrait.pixels) == 512 && CVPixelBufferGetHeight(portrait.pixels) == 1024,
                         "Image import must honor EXIF orientation.")
            let invalid = folder.appendingPathComponent("invalid.png")
            try Data("invalid image".utf8).write(to: invalid)
            do {
                _ = try AppearanceImage.load(from: invalid)
                fatalError("Unreadable images must return an actionable error.")
            } catch AppearanceImage.ImageError.unreadable {}
        } catch { fatalError("Appearance import check failed: \(error)") }
    }

    @MainActor private static func checkPreviewTransition(in screen: NSRect) {
        let rect = NSRect(x: screen.midX - 160, y: screen.midY - 100, width: 320, height: 200)
        var buffer: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 320, 200, kCVPixelFormatType_32BGRA,
                                        nil, &buffer) == kCVReturnSuccess)
        let pixels = buffer!
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels)!, 255, CVPixelBufferGetBytesPerRow(pixels) * 200)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !condition() {
                precondition(Date() < deadline, "Timed out waiting for the real preview renderer or transition.")
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
        }

        let opening = PreviewPresentation(contentRect: rect, reduceMotion: false)
        defer { opening.dispose() }
        opening.start()
        precondition(!opening.isRevealed && opening.frameView.layer!.opacity == 0,
                     "The preview must remain transparent until its first rendered frame.")
        opening.frameView.display(pixels)
        wait { opening.isRevealed }
        precondition(!opening.window.isKeyWindow && !opening.window.canBecomeKey,
                     "Preview animation must not acquire keyboard focus.")
        precondition(opening.frameView.layer!.animation(forKey: "preview.spring") is CASpringAnimation,
                     "The rendered preview must start a native spring transition.")
        let fixedFrame = opening.window.frame
        settle()
        precondition(opening.window.frame == fixedFrame && opening.frameView.bounds.size == rect.size,
                     "Preview animation must preserve window and drawable dimensions.")
        var dismissed = false
        opening.dismiss(animated: true) { dismissed = true }
        precondition(opening.window.ignoresMouseEvents, "A fading preview must immediately release mouse input.")

        let replacement = PreviewPresentation(contentRect: rect, reduceMotion: true)
        defer { replacement.dispose() }
        replacement.start()
        replacement.frameView.display(pixels)
        wait { replacement.isRevealed && dismissed }
        precondition(!opening.window.isVisible && replacement.window.isVisible,
                     "Completing an old dismissal must not close the new preview.")
        precondition(replacement.frameView.layer!.animation(forKey: "preview.spring") == nil,
                     "Reduced motion must show the preview without a spring transform.")

        let cancelled = PreviewPresentation(contentRect: rect)
        cancelled.start()
        cancelled.dismiss(animated: true) {}
        cancelled.frameView.display(pixels)
        settle()
        precondition(!cancelled.window.isVisible && !cancelled.isRevealed,
                     "Cancelling before the first frame must not reveal a late preview.")
        print("Passed native preview first-frame, spring, cancellation, replacement, and reduced-motion checks.")
    }

    @MainActor private static func checkCaptureDetection() {
        func buffer(_ value: UInt8) -> CVPixelBuffer {
            var result: CVPixelBuffer?
            precondition(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &result) == kCVReturnSuccess)
            let pixelBuffer = result!
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            memset(CVPixelBufferGetBaseAddress(pixelBuffer)!, Int32(value), CVPixelBufferGetBytesPerRow(pixelBuffer) * 64)
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return pixelBuffer
        }
        let output = StreamOutput()
        var events: [Bool] = []
        output.onActivity = { events.append($0) }
        output.setRunning(true)
        let original = buffer(80)
        output.queue.sync { output.acceptFrame(original) }
        output.configureIdle(true)
        output.queue.sync {}
        settle()
        precondition(events == [true], "Enabling detection on a static frame must establish a baseline immediately.")
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        let changed = buffer(180)
        output.queue.sync { output.acceptFrame(changed) }
        settle()
        precondition(events == [true, false], "The first change after enabling detection must be reported as a change.")
        output.setRunning(false)
        output.queue.sync { output.acceptFrame(original) }
        settle()
        precondition(events.count == 2, "Stopped capture must not deliver detection events.")
        print("Passed native pixel-buffer baseline, change, and stopped-capture checks.")
    }

    @MainActor private static func checkSurface(in panel: FloatingPanel) {
        panel.setContentSize(NSSize(width: 360, height: 240))
        let surface = PanelSurface(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        panel.contentView = surface
        surface.layoutSubtreeIfNeeded()

        func hit(_ x: CGFloat, _ y: CGFloat) -> NSView? {
            surface.hitTest(surface.convert(NSPoint(x: x, y: y), to: surface.superview))
        }
        func checkButton(_ x: CGFloat, _ y: CGFloat, _ action: PanelAction) {
            surface.layoutSubtreeIfNeeded()
            settle()
            let point = surface.convert(NSPoint(x: x, y: y), to: nil)
            precondition(surface.control(atWindowPoint: point) == action, "Wrong floating panel action.")
            guard let control = hit(x, y), !(control is PanelInput) else {
                fatalError("Expected a native control target at \(x), \(y).")
            }
            precondition(surface.target(atWindowPoint: point) === control,
                         "Window-coordinate targeting must preserve native button handling.")
        }

        precondition(hit(24, 24) is PanelInput, "Hidden controls must leave content interactive.")
        precondition(surface.layer!.masksToBounds == false,
                     "The glass control hierarchy must remain outside the content clipping layer.")
        precondition(surface.frameView.layer!.masksToBounds,
                     "Capture content must still be clipped to its rounded shape.")
        guard let chrome = surface.subviews.compactMap({ $0 as? PanelChromeHost }).first else {
            fatalError("Missing floating control host.")
        }
        precondition(!chrome.isOpaque && !chrome.clipsToBounds,
                     "The glass host must preserve transparency and the effect edges.")
        surface.setHovered(true)
        checkButton(24, 24, .close)
        checkButton(340, 19, .detection)
        checkButton(65, 19, .frameRate)
        precondition(hit(24, 216) is PanelInput, "The lower-left content must receive clicks.")
        checkButton(345, 225, .resize)
        for message in ["捕获已暂停", "Capture paused", "来源窗口位于台前调度的其他分组\n返回来源窗口后继续捕获",
                        "Source is in another Stage Manager group\nReturn to the source to resume capture"] {
            chrome.state.value.message = message
            chrome.state.value.stageInactive = false
            settle()
            wait("The actual status accessibility element must be available.") {
                accessibilityElement(chrome, identifier: "panel.status") != nil
            }
            let rendered = accessibilityElement(chrome, identifier: "panel.status")!.accessibilityFrame()
            precondition(abs(rendered.midX - panel.frame.midX) < 2 && abs(rendered.midY - panel.frame.midY) < 2,
                         "Status text must render at the panel center.")
            for size in [CGSize(width: 180, height: 140), CGSize(width: 360, height: 240)] {
                chrome.state.value.stageInactive = true
                let layout = chrome.state.messageLayout(in: size)
                let action = chrome.state.regions(in: size).first { $0.id == .returnSource }!.frame
                precondition(!layout.message.intersects(action) && layout.message.maxY + 8 <= action.minY,
                             "Multiline status messages must remain clear of the return button.")
                precondition(layout.message.union(action).midY == size.height / 2)
            }
            settle()
            wait("The actual return button accessibility element must be available.") {
                accessibilityElement(chrome, identifier: "panel.returnSource") != nil
            }
            let statusFrame = accessibilityElement(chrome, identifier: "panel.status")!.accessibilityFrame()
            let actionFrame = accessibilityElement(chrome, identifier: "panel.returnSource")!.accessibilityFrame()
            precondition(!statusFrame.intersects(actionFrame), "Rendered status text and return control must not overlap.")
            let button = chrome.state.regions(in: surface.bounds.size).first { $0.id == .returnSource }!.frame
            checkButton(button.midX, button.midY, .returnSource)
        }
        chrome.state.value.message = nil
        chrome.state.value.stageInactive = false
        surface.update(title: "Source", status: "10 FPS", idle: false, detection: true, message: nil)
        checkButton(120, 19, .threshold)
        surface.update(title: "Source", status: "10 FPS", idle: false, detection: false, message: nil)
        guard let content = hit(180, 120) as? PanelInput else { fatalError("The hint must not intercept content clicks.") }
        precondition(content.acceptsFirstMouse(for: nil), "Content must accept the first click.")
        precondition(!content.mouseDownCanMoveWindow, "Content must own mouse-down and mouse-up delivery.")
        precondition(!content.needsPanelToBecomeKey && !panel.canBecomeKey,
                     "Content clicks must work while the floating panel stays non-key.")
        let target = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 240, height: 120),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        target.isReleasedWhenClosed = false
        defer { target.close() }
        surface.onContentClick = { target.makeKeyAndOrderFront(nil) }
        func event(_ type: NSEvent.EventType, at point: NSPoint = NSPoint(x: 180, y: 120),
                   clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: surface.convert(point, to: nil), modifierFlags: modifiers,
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clickCount, pressure: 1)!
        }
        for hovered in [false, true] {
            surface.setHovered(hovered)
            for point in [NSPoint(x: 70, y: 58), NSPoint(x: 180, y: 120), NSPoint(x: 290, y: 184), NSPoint(x: 24, y: 216)] {
                NSApp.postEvent(event(.leftMouseUp, at: point), atStart: true)
                NSApp.sendEvent(event(.leftMouseDown, at: point))
                precondition(target.isVisible, "A content click must focus its destination when tracking completes.")
                target.orderOut(nil)
            }
        }
        NSApp.postEvent(event(.leftMouseUp, at: NSPoint(x: 182, y: 121)), atStart: true)
        NSApp.postEvent(event(.leftMouseDragged, at: NSPoint(x: 181, y: 121)), atStart: true)
        NSApp.sendEvent(event(.leftMouseDown))
        precondition(target.isVisible, "Small pointer jitter must still focus the destination.")
        target.orderOut(nil)
        NSApp.postEvent(event(.leftMouseUp, clickCount: 2), atStart: true)
        NSApp.sendEvent(event(.leftMouseDown, clickCount: 2))
        precondition(!target.isVisible, "The second click must not duplicate the single-click action.")
        NSApp.postEvent(event(.leftMouseUp, at: NSPoint(x: 240, y: 170), modifiers: [.command]), atStart: true)
        NSApp.postEvent(event(.leftMouseDragged, at: NSPoint(x: 240, y: 170), modifiers: [.command]), atStart: true)
        NSApp.sendEvent(event(.leftMouseDown, modifiers: [.command]))
        precondition(!target.isVisible, "Region selection must not focus the destination.")
        let cancel = Timer(timeInterval: 0.01, repeats: false) { _ in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
        RunLoop.main.add(cancel, forMode: .eventTracking)
        NSApp.sendEvent(event(.leftMouseDown))
        panel.orderFrontRegardless()
        NSApp.sendEvent(event(.leftMouseUp))
        precondition(!target.isVisible, "Hiding a panel must cancel the pending click.")
        surface.setHovered(true)
        surface.layoutSubtreeIfNeeded()
        let originalFrame = panel.frame
        let handlePoint = NSPoint(x: 345, y: 225)
        NSApp.postEvent(event(.leftMouseUp, at: NSPoint(x: 375, y: 245)), atStart: true)
        NSApp.postEvent(event(.leftMouseDragged, at: NSPoint(x: 375, y: 245)), atStart: true)
        NSApp.sendEvent(event(.leftMouseDown, at: handlePoint))
        precondition(panel.frame.width > originalFrame.width && panel.frame.height > originalFrame.height,
                     "Dragging the corner handle outward must enlarge the panel.")
        precondition(abs(panel.frame.minX - originalFrame.minX) < 1 && abs(panel.frame.maxY - originalFrame.maxY) < 1,
                     "Corner resizing must keep the top-left corner fixed.")
        precondition(abs(panel.frame.width / panel.frame.height - originalFrame.width / originalFrame.height) < 0.01,
                     "Corner resizing must preserve the content aspect ratio.")
        precondition(!target.isVisible, "Resizing must not activate the content destination.")
        panel.setFrame(originalFrame, display: true)
        surface.layoutSubtreeIfNeeded()
        for shade in surface.subviews.compactMap({ $0 as? PanelDimView }) {
            let center = CGPoint(x: shade.bounds.midX, y: shade.bounds.midY)
            precondition(shade.subviews.allSatisfy { !$0.frame.contains(center) },
                         "Hover shading must leave the center of the capture untouched.")
            precondition(shade.hitTest(center) == nil, "Edge effects must not intercept content input.")
        }
        precondition(hit(-1, 120) == nil, "Points outside the surface must not receive input.")
        surface.isHidden = true
        precondition(hit(180, 120) == nil, "Hidden surfaces must not receive input.")
        surface.isHidden = false

        surface.previewEnabled = false
        precondition(hit(24, 216) is PanelInput, "The lower-left content must remain interactive.")
        checkButton(345, 225, .resize)
        panel.setContentSize(NSSize(width: 120, height: 80))
        surface.layoutSubtreeIfNeeded()
        checkButton(24, 24, .close)
        checkButton(96, 24, .detection)
        precondition(hit(65, 19) is PanelInput, "Compact panels must preserve content between the corner controls.")
        for size in [NSSize(width: 70, height: 180), NSSize(width: 320, height: 30)] {
            panel.setContentSize(size)
            surface.layoutSubtreeIfNeeded()
            let center = surface.convert(CGPoint(x: size.width / 2, y: size.height / 2), to: nil)
            precondition(surface.control(atWindowPoint: center) == nil,
                         "Very narrow content must not be covered by overlapping controls.")
            precondition(surface.target(atWindowPoint: center) is PanelInput)
        }

        panel.setContentSize(NSSize(width: 360, height: 240))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        panel.contentView = container
        surface.frame = NSRect(x: 30, y: 40, width: 120, height: 80)
        container.addSubview(surface)
        checkButton(24, 24, .close)
        checkButton(96, 24, .detection)
        print("Passed native control targeting, first-click acceptance, compact layout, and flipped-coordinate checks.")
    }

    @MainActor private static func makePanel(_ frame: NSRect) -> FloatingPanel {
        let panel = FloatingPanel(contentRect: frame, styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.white.cgColor
        panel.contentView = content
        return panel
    }

    @MainActor private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
}
