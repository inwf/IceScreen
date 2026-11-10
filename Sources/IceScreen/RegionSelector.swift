#if os(macOS)
import AppKit
import IceCore

final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class RegionSelector {
    private var panel: NSPanel?
    private var completion: ((Viewport?) -> Void)?

    func select(frame: CGRect, completion: @escaping (Viewport?) -> Void) {
        cancel()
        self.completion = completion
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screenFrame = CGRect(x: frame.minX, y: desktopTop - frame.maxY, width: frame.width, height: frame.height)
        let panel = SelectionPanel(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let surface = RegionSurface(frame: CGRect(origin: .zero, size: frame.size))
        surface.onSelection = { [weak self] rect in self?.finish(rect.map { Viewport(rect: $0) }) }
        panel.contentView = surface
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(surface)
    }

    func cancel() { finish(nil) }

    private func finish(_ result: Viewport?) {
        panel?.orderOut(nil)
        panel = nil
        let callback = completion
        completion = nil
        callback?(result)
    }
}

final class RegionSurface: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var onSelection: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.36).setFill()
        bounds.fill()
        if let selection {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            CaptureSelectionStyle.color.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 2
            border.stroke()
        }
        let message = "拖动选择捕获区域 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white
        ]
        message.draw(at: CGPoint(x: 20, y: 20), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        guard let selection, selection.width >= 4, selection.height >= 4 else { return }
        onSelection?(CGRect(x: selection.minX / bounds.width, y: selection.minY / bounds.height,
                            width: selection.width / bounds.width, height: selection.height / bounds.height))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSelection?(nil) }
    }
    override func rightMouseDown(with event: NSEvent) { onSelection?(nil) }
}
#endif
