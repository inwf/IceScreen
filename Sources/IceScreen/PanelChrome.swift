#if os(macOS)
import AppKit
import SwiftUI

enum PanelAction: String, CaseIterable {
    case close, frameRate, threshold, detection, resize

    var label: String {
        switch self {
        case .close: return "关闭浮窗"
        case .frameRate: return "应用帧率 · F"
        case .threshold: return "检测等待时间"
        case .detection: return "内容检测"
        case .resize: return "拖动调整浮窗大小"
        }
    }
}

struct PanelControlRegion: Identifiable {
    let id: PanelAction
    let frame: CGRect
}

@MainActor
final class PanelChromeState: ObservableObject {
    struct Value: Equatable {
        var hovered = false
        var detection = false
        var changeDetection = false
        var idle = false
        var fps = 10
        var threshold = 20.0
        var showHints = true
        var showModifierHints = false
        var clickToFocus = true
        var zoomed = false
        var trigger = "fn"
        var message: String?
    }
    @Published var value = Value()
    var perform: ((PanelAction) -> Void)?

    var detectionTitle: String { value.idle ? "已空闲" : (value.detection ? "检测中" : "未启用") }
    var detectionHelp: String {
        "内容检测：" + detectionTitle + "。点击选择空闲提醒、变化提醒或细微变化。"
    }

    func regions(in size: CGSize) -> [PanelControlRegion] {
        var items: [PanelControlRegion] = []
        if value.hovered {
            items.append(.init(id: .close, frame: CGRect(x: 8, y: 8, width: 22, height: 22)))
            if size.width >= 150 {
                items.append(.init(id: .frameRate, frame: CGRect(x: 38, y: 9, width: 55, height: 20)))
                if value.detection && size.width >= 220 {
                    items.append(.init(id: .threshold, frame: CGRect(x: 99, y: 9, width: 44, height: 20)))
                }
            }
            if size.height >= 70 {
                items.append(.init(id: .resize, frame: CGRect(x: size.width - 25, y: size.height - 25, width: 21, height: 21)))
            }
        }
        if value.hovered || value.detection {
            items.append(.init(id: .detection, frame: CGRect(x: size.width - 30, y: 8, width: 22, height: 22)))
        }
        return items
    }
}

struct PanelChrome: View {
    @ObservedObject var state: PanelChromeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detectionColor: Color { state.value.changeDetection ? .blue : .green }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                hints(in: geometry.size).allowsHitTesting(false)
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 0) { controls(in: geometry.size) }
                } else {
                    controls(in: geometry.size)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .environment(\.controlActiveState, .key)
    }

    private func controls(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(state.regions(in: size)) { region in
                control(region.id)
                    .frame(width: region.frame.width, height: region.frame.height)
                    .position(x: region.frame.midX, y: region.frame.midY)
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder private func hints(in size: CGSize) -> some View {
        if state.value.hovered && state.value.showHints && size.width >= 210 && size.height >= 100 {
            VStack(spacing: 2) {
                Text(state.value.zoomed ? "⌘ 拖动放大 · ⌘ 双击重置" : "⌘ 拖动放大 · ⌫ 关闭")
                Text(state.value.clickToFocus ? "单击定位 · 双击定位并关闭" : "双击定位并关闭")
            }
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.34), radius: 1)
            .lineLimit(1)
            .frame(width: size.width - 48, height: 30)
            .position(x: size.width / 2, y: size.height - 23)
        }
        if let message = state.value.message {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: max(0, size.width - 32))
                .position(x: size.width / 2, y: size.height / 2)
        } else if state.value.showModifierHints && size.width >= 210 && size.height >= 140 {
            VStack(spacing: 6) {
                Text("轻按 \(state.value.trigger) 隐藏")
                Text("双击 \(state.value.trigger) 切换自动隐藏")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.6), radius: 2)
            .frame(width: size.width - 32)
            .position(x: size.width / 2, y: size.height / 2)
        }
    }

    @ViewBuilder private func control(_ action: PanelAction) -> some View {
        if action == .resize {
            if #available(macOS 26.0, *) {
                resizeLabel.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 5))
                    .allowsHitTesting(false)
            } else {
                resizeLabel.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                    .allowsHitTesting(false)
            }
        } else if #available(macOS 26.0, *) {
            button(action)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(action == .frameRate || action == .threshold ? .capsule : .circle)
        } else {
            button(action).buttonStyle(.bordered)
        }
    }

    private var resizeLabel: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.primary)
            .frame(width: 21, height: 21)
    }

    private func button(_ action: PanelAction) -> some View {
        Button { state.perform?(action) } label: {
            label(action).contentShape(Rectangle())
        }
        .controlSize(.mini)
        .tint(tint(for: action))
        .focusable(false)
        .help(action == .detection ? state.detectionHelp : action.label)
        .accessibilityLabel(action.label)
        .accessibilityValue(action == .detection ? state.detectionTitle : "")
        .accessibilityIdentifier("panel.\(action.rawValue)")
    }

    private func tint(for action: PanelAction) -> Color {
        switch action {
        case .close: return .red
        case .frameRate: return .orange
        case .threshold: return detectionColor
        case .detection: return state.value.detection ? detectionColor : .gray
        case .resize: return .accentColor
        }
    }

    @ViewBuilder private func label(_ action: PanelAction) -> some View {
        switch action {
        case .close:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12, height: 12)
        case .frameRate:
            Text("\(state.value.fps) FPS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        case .threshold:
            Text("\(Int(state.value.threshold))s")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        case .detection:
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .frame(width: 12, height: 12)
                .symbolEffect(.pulse, options: .repeating, isActive: state.value.idle && !reduceMotion)
        case .resize:
            EmptyView()
        }
    }
}

struct PanelEdgeScrim: View {
    let top: Bool
    let strength: Double

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(.black.opacity(0.6))
            .mask(LinearGradient(colors: [.black, .clear],
                                 startPoint: top ? .top : .bottom,
                                 endPoint: top ? .bottom : .top))
            .opacity(strength)
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
    }
}

final class PanelChromeHost: NSHostingView<PanelChrome> {
    let state: PanelChromeState

    init(state: PanelChromeState) {
        self.state = state
        super.init(rootView: PanelChrome(state: state))
        sizingOptions = []
    }

    required init(rootView: PanelChrome) {
        state = rootView.state
        super.init(rootView: rootView)
        sizingOptions = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    func region(at point: CGPoint) -> PanelControlRegion? {
        state.regions(in: bounds.size).first { $0.frame.contains(point) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let region = region(at: convert(point, from: superview)), region.id != .resize else { return nil }
        return super.hitTest(point) ?? self
    }
}
#endif
