#if os(macOS)
import AppKit
import SwiftUI
import IceCore

enum PanelAction: String, CaseIterable {
    case close, frameRate, threshold, detection, resize, playPause, previousTrack, nextTrack, seek

    var label: String {
        switch self {
        case .close: return "关闭浮窗"
        case .frameRate: return "应用帧率 · F"
        case .threshold: return "检测等待时间"
        case .detection: return "内容检测"
        case .resize: return "拖动调整浮窗大小"
        case .playPause: return "播放或暂停 · Space"
        case .previousTrack: return "上一首"
        case .nextTrack: return "下一首"
        case .seek: return "播放进度 · ← → 调整 5 秒"
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
        var clickToFocus = true
        var previewEnabled = true
        var zoomed = false
        var message: String?
        var media: MediaSnapshot?
        var mediaSeek = true
    }
    @Published var value = Value()
    var perform: ((PanelAction) -> Void)?
    var seek: ((Double) -> Void)?
    var seeking: ((Bool) -> Void)?

    var detectionTitle: String { value.idle ? "已空闲" : (value.detection ? "检测中" : "未启用") }
    var detectionHelp: String {
        "内容检测：" + detectionTitle + "。点击选择空闲提醒、变化提醒或细微变化。"
    }

    func regions(in size: CGSize) -> [PanelControlRegion] {
        guard size.width >= 80, size.height >= 46 else { return [] }
        var items: [PanelControlRegion] = []
        if value.hovered {
            items.append(.init(id: .close, frame: CGRect(x: 8, y: 8, width: 30, height: 30)))
            if size.width >= 190 {
                items.append(.init(id: .frameRate, frame: CGRect(x: 46, y: 8, width: 64, height: 30)))
                if value.detection && size.width >= 240 {
                    items.append(.init(id: .threshold, frame: CGRect(x: 118, y: 8, width: 52, height: 30)))
                }
            }
            if size.height >= 80 {
                items.append(.init(id: .resize, frame: CGRect(x: size.width - 38, y: size.height - 38, width: 30, height: 30)))
            }
            if let media = value.media, size.height >= 100, size.width >= 150 {
                let hasSeek = value.mediaSeek && media.seekable && size.height >= 145 && size.width >= 230
                let y = size.height - (hasSeek ? 80 : 40)
                items.append(.init(id: .playPause, frame: CGRect(x: size.width / 2 - 15, y: y, width: 30, height: 30)))
                if size.width >= 230 {
                    items.append(.init(id: .previousTrack, frame: CGRect(x: size.width / 2 - 53, y: y, width: 30, height: 30)))
                    items.append(.init(id: .nextTrack, frame: CGRect(x: size.width / 2 + 23, y: y, width: 30, height: 30)))
                }
                if hasSeek {
                    items.append(.init(id: .seek, frame: CGRect(x: 12, y: size.height - 43, width: size.width - 62, height: 36)))
                }
            }
        }
        if value.hovered || value.detection {
            items.append(.init(id: .detection, frame: CGRect(x: size.width - 38, y: 8, width: 30, height: 30)))
        }
        return items
    }
}

struct PanelChrome: View {
    @ObservedObject var state: PanelChromeState
    @Namespace private var glassNamespace
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
        if state.value.hovered && state.value.showHints && state.value.message == nil && state.value.media == nil && size.width >= 210 && size.height >= 110 {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    hintKey(state.value.clickToFocus ? "单击" : "双击",
                            state.value.clickToFocus ? "返回来源" : "返回并关闭")
                    if state.value.previewEnabled && size.width >= 300 {
                        hintKey("Space", "预览")
                    }
                }
                Text(state.value.zoomed ? "拖动移动 · ⌘ 双击恢复画面" : "拖动移动 · ⌘ 拖动放大")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .lineLimit(1)
            .frame(width: size.width - 66, height: 38, alignment: .leading)
            .position(x: 12 + (size.width - 66) / 2, y: size.height - 30)
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
        }
    }

    private func hintKey(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
            Text(action)
        }
    }

    @ViewBuilder private func control(_ action: PanelAction) -> some View {
        if action == .seek, let snapshot = state.value.media {
            MediaSeekControl(snapshot: snapshot, seek: { state.seek?($0) }, editing: { state.seeking?($0) })
        } else if action == .resize {
            if #available(macOS 26.0, *) {
                resizeLabel.glassEffect(.clear, in: .circle)
                    .glassEffectID(action, in: glassNamespace)
                    .glassEffectTransition(.materialize)
                    .allowsHitTesting(false)
            } else {
                resizeLabel.background(.regularMaterial, in: Circle())
                    .allowsHitTesting(false)
            }
        } else if #available(macOS 26.0, *) {
            button(action)
                .buttonStyle(.glass(.clear.interactive()))
                .buttonSizing(.flexible)
                .buttonBorderShape(action == .frameRate || action == .threshold ? .capsule : .circle)
                .glassEffectID(action, in: glassNamespace)
                .glassEffectTransition(.materialize)
        } else {
            button(action).buttonStyle(.bordered)
        }
    }

    private var resizeLabel: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
    }

    private func button(_ action: PanelAction) -> some View {
        Button { state.perform?(action) } label: {
            label(action).contentShape(Rectangle())
        }
        .controlSize(.regular)
        .focusable(false)
        .help(action == .detection ? state.detectionHelp : action.label)
        .accessibilityLabel(action.label)
        .accessibilityValue(action == .detection ? state.detectionTitle : "")
        .accessibilityIdentifier("panel.\(action.rawValue)")
    }

    @ViewBuilder private func label(_ action: PanelAction) -> some View {
        switch action {
        case .close:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14, height: 14)
        case .frameRate:
            Text("\(state.value.fps) FPS")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        case .threshold:
            Text("\(Int(state.value.threshold))s")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        case .detection:
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(state.value.detection ? detectionColor : .secondary)
                .frame(width: 14, height: 14)
                .symbolEffect(.pulse, options: .repeating, isActive: state.value.idle && !reduceMotion)
        case .resize:
            EmptyView()
        case .playPause:
            Image(systemName: state.value.media?.playing == true ? "pause.fill" : "play.fill").font(.system(size: 12))
        case .previousTrack:
            Image(systemName: "backward.end.fill").font(.system(size: 12))
        case .nextTrack:
            Image(systemName: "forward.end.fill").font(.system(size: 12))
        case .seek:
            EmptyView()
        }
    }
}

private struct MediaSeekControl: View {
    let snapshot: MediaSnapshot
    let seek: (Double) -> Void
    let editing: (Bool) -> Void
    @State private var dragging = false
    @State private var value = 0.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = max(1, snapshot.duration ?? 1)
            let position = dragging ? value : snapshot.position(at: context.date.timeIntervalSince1970)
            VStack(spacing: 0) {
                Slider(value: Binding(get: { min(duration, position) }, set: { value = $0 }), in: 0...duration) { active in
                    if active { value = position }
                    dragging = active
                    editing(active)
                    if !active { seek(value) }
                }
                .controlSize(.mini).focusable(false).tint(.white)
                .accessibilityLabel("播放进度")
                HStack { Text(time(position)); Spacer(); Text(time(duration)) }
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1)
            }
        }
        .onDisappear { if dragging { dragging = false; editing(false) } }
    }
    private func time(_ seconds: Double) -> String {
        let value = Int(min(359999, max(0, seconds)))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct PanelEdgeScrim: View {
    let top: Bool
    let strength: Double

    var body: some View {
        LinearGradient(colors: [.black.opacity(0.6), .clear],
                       startPoint: top ? .top : .bottom,
                       endPoint: top ? .bottom : .top)
            .opacity(strength)
            .allowsHitTesting(false)
    }
}

final class PanelChromeHost: NSHostingView<PanelChrome> {
    let state: PanelChromeState
    override var isOpaque: Bool { false }

    init(state: PanelChromeState) {
        self.state = state
        super.init(rootView: PanelChrome(state: state))
        configureHosting()
    }

    required init(rootView: PanelChrome) {
        state = rootView.state
        super.init(rootView: rootView)
        configureHosting()
    }
    private func configureHosting() {
        sizingOptions = []
        safeAreaRegions = []
        wantsLayer = true
        clipsToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
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
