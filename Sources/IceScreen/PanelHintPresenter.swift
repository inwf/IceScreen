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
        let host = PanelHintHost(rootView: PanelHint(message: message))
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.frame = CGRect(origin: .zero, size: frame.size)
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

private final class PanelHintHost: NSHostingView<PanelHint> {
    override var isOpaque: Bool { false }
}

private struct PanelHint: View {
    let message: String
    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(x: 8, y: 8, width: max(0, geometry.size.width - 16), height: max(0, geometry.size.height - 16))
            let size = PanelMessage.size(for: message, width: min(380, bounds.width), style: .hint)
            let layout = PanelMessageLayout(in: bounds, messageSize: size)
            PanelMessage(message: message, style: .hint)
                .frame(width: layout.message.width, height: layout.message.height)
                .position(x: layout.message.midX, y: layout.message.midY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .clipped()
    }
}
#endif
