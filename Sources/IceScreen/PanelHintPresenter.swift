#if os(macOS)
import AppKit
import SwiftUI

/// 提示使用独立的穿透面板，浮窗自动隐藏后仍可读到切换结果。
@MainActor
final class PanelHintPresenter {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(_ message: String, near anchor: CGRect) {
        close()
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }
        guard let visible = screen?.visibleFrame else { return }
        let size = CGSize(width: 220, height: 44)
        let origin = CGPoint(x: min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8),
                             y: min(max(anchor.midY - size.height / 2, visible.minY + 8), visible.maxY - size.height - 8))
        let window = FloatingPanel(contentRect: CGRect(origin: origin, size: size),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: PanelHint(message: message))
        panel = window
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            window.animator().alphaValue = 1
        }
        dismissal = Task { [weak self, weak window] in
            do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
            guard let self, let window, self.panel === window else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window.animator().alphaValue = 0
            }
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            if self.panel === window { self.close() }
        }
    }

    func close() {
        dismissal?.cancel()
        dismissal = nil
        panel?.close()
        panel = nil
    }
}

private struct PanelHint: View {
    let message: String
    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                label.glassEffect(.regular, in: .capsule)
            } else {
                label.background(.regularMaterial, in: Capsule())
            }
        }.padding(4)
    }
    private var label: some View {
        Text(message).font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18).frame(height: 36)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif
