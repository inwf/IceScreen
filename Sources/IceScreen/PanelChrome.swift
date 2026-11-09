#if os(macOS)
import AppKit
import SwiftUI

enum PanelAction: String, CaseIterable {
    case close, detection, preview, menu

    var symbol: String {
        switch self {
        case .close: return "xmark"
        case .detection: return "waveform.path"
        case .preview: return "arrow.up.left.and.arrow.down.right"
        case .menu: return "ellipsis"
        }
    }

    var label: String {
        switch self {
        case .close: return "关闭浮窗"
        case .detection: return "内容检测"
        case .preview: return "预览来源窗口 · Space"
        case .menu: return "浮窗设置"
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
        var idle = false
        var preview = true
    }
    @Published var value = Value()
    var perform: ((PanelAction) -> Void)?

    var detectionTitle: String { value.idle ? "已空闲" : (value.detection ? "检测中" : "检测") }
    var detectionHelp: String {
        "内容检测：" + (value.detection ? (value.idle ? "内容已停止变化" : "正在监测") : "尚未启用")
            + "。点击选择空闲提醒、变化提醒或细微变化。"
    }

    func regions(in size: CGSize) -> [PanelControlRegion] {
        let compact = size.width < 180 || size.height < 100
        var items: [PanelControlRegion] = []
        if value.hovered {
            items.append(.init(id: .close, frame: CGRect(x: 8, y: 8, width: 32, height: 32)))
            items.append(.init(id: .menu, frame: CGRect(x: size.width - 40,
                y: compact ? 8 : size.height - 40, width: 32, height: 32)))
            if !compact {
                if value.preview {
                    items.append(.init(id: .preview, frame: CGRect(x: size.width - 80,
                        y: size.height - 40, width: 32, height: 32)))
                }
            }
        }
        if !compact && (value.hovered || value.detection) {
            items.append(.init(id: .detection, frame: CGRect(x: size.width - 96, y: 8, width: 88, height: 32)))
        }
        return items
    }
}

struct PanelChrome: View {
    @ObservedObject var state: PanelChromeState

    var body: some View {
        GeometryReader { geometry in
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { buttons(in: geometry.size) }
            } else {
                buttons(in: geometry.size)
            }
        }
        .environment(\.controlActiveState, .key)
        .font(.system(size: 12, weight: .medium))
    }

    private func buttons(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(state.regions(in: size)) { region in
                control(region.id)
                    .frame(width: region.frame.width, height: region.frame.height)
                    .position(x: region.frame.midX, y: region.frame.midY)
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder private func control(_ action: PanelAction) -> some View {
        if #available(macOS 26.0, *) {
            if action == .detection {
                button(action).buttonStyle(.glass).buttonBorderShape(.capsule)
            } else {
                button(action).buttonStyle(.glass).buttonBorderShape(.circle)
            }
        } else {
            button(action).buttonStyle(.bordered)
        }
    }

    private func button(_ action: PanelAction) -> some View {
        Button { state.perform?(action) } label: {
            HStack(spacing: 4) {
                Image(systemName: action.symbol)
                if action == .detection { Text(state.detectionTitle) }
            }
            .frame(minWidth: action == .detection ? 64 : 16, minHeight: 20)
        }
        .controlSize(.large)
        .focusable(false)
        .help(action == .detection ? state.detectionHelp : action.label)
        .accessibilityLabel(action.label)
        .accessibilityValue(action == .detection ? state.detectionTitle : "")
        .accessibilityIdentifier("panel.\(action.rawValue)")
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
        guard !isHidden, region(at: convert(point, from: superview)) != nil else { return nil }
        return super.hitTest(point) ?? self
    }
}
#endif
