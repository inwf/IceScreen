#if os(macOS)
import AppKit
import SwiftUI
import IceCore

enum PanelAction: String, CaseIterable {
    case close, frameRate, threshold, detection, resize, playPause, previousTrack, nextTrack, seek, returnSource

    var label: String {
        switch self {
        case .close: return L10n.text("关闭浮窗", "Close panel")
        case .frameRate: return L10n.text("应用帧率 · F", "App frame rate · F")
        case .threshold: return L10n.text("检测等待时间", "Detection wait time")
        case .detection: return L10n.text("内容检测", "Content detection")
        case .resize: return L10n.text("拖动调整浮窗大小", "Drag to resize panel")
        case .playPause: return L10n.text("播放或暂停 · Space", "Play or pause · Space")
        case .previousTrack: return L10n.text("上一首", "Previous track")
        case .nextTrack: return L10n.text("下一首", "Next track")
        case .seek: return L10n.text("播放进度 · ← → 调整 5 秒", "Playback progress · ← → seek 5 seconds")
        case .returnSource: return L10n.text("返回来源窗口", "Return to source")
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
        var language = L10n.language
        var hovered = false
        var sourceAppName: String?
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
        var stageInactive = false
    }
    @Published var value = Value()
    var perform: ((PanelAction) -> Void)?
    var seek: ((Double) -> Void)?
    var seeking: ((Bool) -> Void)?

    var detectionTitle: String {
        value.idle ? L10n.text("已空闲", "Idle", language: value.language)
            : (value.detection ? L10n.text("检测中", "Detecting", language: value.language) : L10n.text("未启用", "Disabled", language: value.language))
    }
    var detectionHelp: String {
        L10n.text("内容检测：\(detectionTitle)。点击选择空闲提醒、变化提醒或细微变化。",
                  "Content detection: \(detectionTitle). Click to select idle, change, or subtle detection.", language: value.language)
    }

    func messageLayout(in size: CGSize) -> PanelMessageLayout {
        let inset: CGFloat = (value.hovered || value.detection) && size.width >= 80 && size.height >= 46 ? 40 : 8
        let bounds = CGRect(x: 8, y: min(inset, size.height / 2),
                            width: max(0, size.width - 16), height: max(0, size.height - inset * 2))
        let messageSize = PanelMessage.size(for: value.message ?? "", width: min(380, bounds.width), style: .status)
        let action = value.stageInactive && size.width >= 180 && size.height >= 140 && bounds.height >= 60
            ? CGSize(width: 124, height: 30) : nil
        return PanelMessageLayout(in: bounds, messageSize: messageSize, actionSize: action)
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
            if let media = value.media, !value.stageInactive,
               let row = MediaButtonLayout(size: size, seekable: value.mediaSeek && media.seekable) {
                items.append(.init(id: .playPause, frame: row.play))
                if let previous = row.previous { items.append(.init(id: .previousTrack, frame: previous)) }
                if let next = row.next { items.append(.init(id: .nextTrack, frame: next)) }
                if let seek = row.seek { items.append(.init(id: .seek, frame: seek)) }
            }
        }
        if value.hovered || value.detection {
            items.append(.init(id: .detection, frame: CGRect(x: size.width - 38, y: 8, width: 30, height: 30)))
        }
        if value.stageInactive, let frame = messageLayout(in: size).action {
            items.append(.init(id: .returnSource, frame: frame))
        }
        return items
    }

    func sourceNameFrame(in size: CGSize) -> CGRect? {
        guard value.hovered, value.sourceAppName?.isEmpty == false, size.height >= 30 else { return nil }
        let buttons = regions(in: size)
        let leading = buttons.filter { [.close, .frameRate, .threshold].contains($0.id) }.map(\.frame.maxX).max()
        let trailing = buttons.first { $0.id == .detection }?.frame.minX
        let left = leading.map { $0 + 4 } ?? 8
        let right = trailing.map { $0 - 4 } ?? size.width - 8
        guard right - left >= 32 else { return nil }
        let frame = CGRect(x: left, y: 13, width: right - left, height: 20)
        if buttons.contains(where: { $0.frame.intersects(frame) }) { return nil }
        if value.message != nil, messageLayout(in: size).message.intersects(frame) { return nil }
        return frame
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
                if let name = state.value.sourceAppName, let frame = state.sourceNameFrame(in: geometry.size) {
                    Text(verbatim: name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("panel.sourceAppName")
                }
                if #available(macOS 26.0, *) {
                    GlassEffectContainer(spacing: 0) { controls(in: geometry.size) }
                } else {
                    controls(in: geometry.size)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .environment(\.controlActiveState, .key)
        .environment(\.locale, state.value.language.locale)
    }

    private func controls(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(state.regions(in: size)) { region in
                control(region.id, diameter: region.frame.height)
                    .frame(width: region.frame.width, height: region.frame.height)
                    .position(x: region.frame.midX, y: region.frame.midY)
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder private func hints(in size: CGSize) -> some View {
        if state.value.hovered && state.value.showHints && state.value.message == nil && state.value.media == nil && size.width >= 210 && size.height >= 110 {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    hintKey(state.value.clickToFocus ? L10n.text("单击", "Click") : L10n.text("双击", "Double-click"),
                            state.value.clickToFocus ? L10n.text("切换窗口", "Switch") : L10n.text("返回并关闭", "Focus & close"))
                    if state.value.previewEnabled && size.width >= 300 {
                        hintKey("Space", L10n.text("预览", "Preview"))
                    }
                }
                Text(state.value.zoomed ? L10n.text("拖动移动 · ⌘ 双击恢复画面", "Drag to move · ⌘ double-click to reset") : L10n.text("拖动移动 · ⌘ 拖动放大", "Drag to move · ⌘ drag to zoom"))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.85))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: size.width - 66, height: 38, alignment: .leading)
            .position(x: 12 + (size.width - 66) / 2, y: size.height - 30)
        }
        if let message = state.value.message {
            let frame = state.messageLayout(in: size).message
            if frame.height >= 20 {
                PanelStatusMessage(message: message)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
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

    @ViewBuilder private func control(_ action: PanelAction, diameter: CGFloat) -> some View {
        if action == .returnSource {
            PanelReturnButton(title: action.label) { state.perform?(action) }
        } else if action == .seek, let snapshot = state.value.media {
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
            button(action, diameter: diameter)
                .buttonStyle(.glass(.clear.interactive()))
                .buttonSizing(.flexible)
                .buttonBorderShape(action == .frameRate || action == .threshold ? .capsule : .circle)
                .glassEffectID(action, in: glassNamespace)
                .glassEffectTransition(.materialize)
        } else if action == .playPause || action == .previousTrack || action == .nextTrack {
            button(action, diameter: diameter, fillMediaTarget: true)
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
        } else {
            button(action, diameter: diameter).buttonStyle(.bordered)
        }
    }

    private var resizeLabel: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
    }

    private func button(_ action: PanelAction, diameter: CGFloat, fillMediaTarget: Bool = false) -> some View {
        Button { state.perform?(action) } label: {
            label(action)
                .font(.system(size: diameter * 0.4))
                .frame(width: fillMediaTarget ? diameter : nil, height: fillMediaTarget ? diameter : nil)
                .contentShape(Rectangle())
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
        case .resize, .returnSource:
            EmptyView()
        case .playPause:
            Image(systemName: state.value.media?.playing == true ? "pause.fill" : "play.fill")
        case .previousTrack:
            Image(systemName: "backward.end.fill")
        case .nextTrack:
            Image(systemName: "forward.end.fill")
        case .seek:
            EmptyView()
        }
    }
}

private struct PanelReturnButton: NSViewRepresentable {
    let title: String
    let perform: () -> Void

    final class Button: NSButton {
        var onPress: (() -> Void)?
        @objc func press() { onPress?() }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var needsPanelToBecomeKey: Bool { false }
    }
    func makeNSView(context: Context) -> Button {
        let button = Button(title: title, target: nil, action: #selector(Button.press))
        button.target = button
        button.font = .systemFont(ofSize: 12)
        button.refusesFirstResponder = true
        button.setAccessibilityIdentifier("panel.returnSource")
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
            button.borderShape = .capsule
        } else {
            button.bezelStyle = .rounded
        }
        return button
    }
    func updateNSView(_ button: Button, context: Context) {
        button.title = title
        button.toolTip = title
        button.onPress = perform
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
                .accessibilityLabel(L10n.text("播放进度", "Playback progress"))
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
