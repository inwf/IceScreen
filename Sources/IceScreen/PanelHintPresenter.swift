#if os(macOS)
import AppKit
import SwiftUI
import IceCore

/// 提示使用独立的穿透面板，浮窗自动隐藏后仍可读到切换结果。
@MainActor
final class PanelHintPresenter {
    private(set) var panel: NSPanel?
    private weak var source: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var dismissal: Task<Void, Never>?

    func show(_ message: String, over source: NSWindow, duration: TimeInterval = 4) {
        close()
        self.source = source
        let frame = source.contentRect(forFrameRect: source.frame)
        let window = FloatingPanel(contentRect: frame,
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = PanelHintHost(message: message, size: frame.size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        panel = window
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: source, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFrame() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: source, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            window.animator().alphaValue = 1
        }
        dismissal = Task { [weak self, weak window] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard let self, let window, self.panel === window else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.15
                window.animator().alphaValue = 0
            }
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            if self.panel === window { self.close() }
        }
    }

    private func updateFrame() {
        guard let source else { close(); return }
        panel?.setFrame(source.contentRect(forFrameRect: source.frame), display: true)
    }

    func close() {
        dismissal?.cancel()
        dismissal = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        source = nil
        panel?.close()
        panel = nil
    }
}

private final class PanelHintHost: NSView {
    let bubble: PanelMessageHost
    override var isOpaque: Bool { false }

    init(message: String, size: CGSize) {
        bubble = PanelMessageHost(rootView: PanelMessage(message: message, style: .hint))
        super.init(frame: CGRect(origin: .zero, size: size))
        addSubview(bubble)
        setAccessibilityChildren([bubble])
        needsLayout = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        let area = CGRect(x: 8, y: 8, width: max(0, bounds.width - 16), height: max(0, bounds.height - 16))
        let size = PanelMessage.size(for: bubble.rootView.message, width: min(380, area.width), style: .hint)
        bubble.frame = PanelMessageLayout(in: area, messageSize: size).message
    }
}
#endif
