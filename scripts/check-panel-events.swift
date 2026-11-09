import AppKit
import CoreVideo
import QuartzCore
import IceCore
import ImageIO
import UniformTypeIdentifiers

@main
enum PanelEventChecks {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        guard let screen = NSScreen.main else { fatalError("Panel checks require an active macOS graphical session.") }
        let frame = NSRect(x: screen.visibleFrame.midX - 90, y: screen.visibleFrame.midY - 70, width: 180, height: 140)
        let lower = makePanel(frame)
        let upper = makePanel(frame.offsetBy(dx: 20, dy: 20))
        defer { lower.close(); upper.close() }
        let point = NSPoint(x: frame.midX, y: frame.midY)
        let panels = [lower, upper]

        lower.orderFrontRegardless()
        upper.orderFrontRegardless()
        settle()
        precondition(PanelHitTesting.frontmost(at: point, among: panels) === upper, "Visible NSPanel must receive hover actions.")
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
        print("Passed 5 native NSPanel hit-testing checks.")
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
            precondition(Date() < deadline, "Appearance sample must render through the real Metal renderer.")
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
                precondition(Date() < deadline, "An imported image must render through the real Metal path.")
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
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        return panel
    }

    @MainActor private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
}
