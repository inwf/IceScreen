import AppKit
import CoreVideo

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
        print("Passed 5 native NSPanel hit-testing checks.")
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
