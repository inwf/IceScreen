#if os(macOS)
import AppKit

final class PanelResizeHandle: NSControl {
    weak var owner: CaptureSession?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "拖动调整浮窗大小"
        setAccessibilityLabel("调整浮窗大小")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let original = window.frame
        let origin = window.convertPoint(toScreen: event.locationInWindow)
        let ratio = original.width / original.height
        let visible = window.screen?.visibleFrame
        let minimum = max(window.minSize.width, window.minSize.height * ratio)
        let maximum = visible.map { max(minimum, min($0.maxX - original.minX, (original.maxY - $0.minY) * ratio)) }
        owner?.beginHandleResize()
        defer { owner?.endHandleResize() }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: 0.1, mode: .eventTracking) { next, stop in
            guard window.isVisible, !window.ignoresMouseEvents else { stop.pointee = true; return }
            guard let next else {
                if NSEvent.pressedMouseButtons & 1 == 0 { stop.pointee = true }
                return
            }
            let point = window.convertPoint(toScreen: next.locationInWindow)
            let dx = point.x - origin.x
            let dy = (origin.y - point.y) * ratio
            let delta = abs(dx) >= abs(dy) ? dx : dy
            let width = max(minimum, min(original.width + delta, maximum ?? .greatestFiniteMagnitude))
            let height = width / ratio
            window.setFrame(NSRect(x: original.minX, y: original.maxY - height, width: width, height: height), display: true)
            if next.type == .leftMouseUp { stop.pointee = true }
        }
    }
}
#endif
