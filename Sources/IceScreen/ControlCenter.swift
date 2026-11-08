#if os(macOS)
import AppKit
import SwiftUI
import ScreenCaptureKit
import IceCore

private enum IceTheme {
    static let ink = Color(red: 0.07, green: 0.15, blue: 0.22)
    static let accent = Color(red: 0.05, green: 0.52, blue: 0.62)
    static let background = Color(red: 0.95, green: 0.97, blue: 0.98)
}

struct ControlCenter: View {
    @ObservedObject var model: ApplicationModel
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                if !model.screenPermission || !model.accessibilityPermission { permissions }
                switch model.selectedPage {
                case "sessions": SessionList(model: model)
                case "settings": SettingsView(model: model, store: model.settings)
                case "guide": GuideView(shortcut: model.settings.value.shortcut.display)
                default: WindowList(model: model, catalog: model.catalog)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(IceTheme.background)
        }
        .frame(minWidth: 820, minHeight: 580)
        .foregroundStyle(IceTheme.ink)
        .tint(IceTheme.accent)
        .preferredColorScheme(.light)
        .alert("IceScreen", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("IceScreen").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("留住你关注的画面").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }.padding(.bottom, 36).padding(.top, 16)
            navigation("windows", "选择窗口", "rectangle.on.rectangle")
            navigation("sessions", "正在关注", "square.stack.3d.up", count: model.sessions.count)
            navigation("settings", "偏好设置", "slider.horizontal.3")
            navigation("guide", "使用指南", "keyboard")
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(model.sessions.isEmpty ? .gray : .mint).frame(width: 6, height: 6)
                    Text(model.sessions.isEmpty ? "随时准备就绪" : "\(model.sessions.count) 个浮窗运行中")
                        .font(.system(size: 12))
                }
                Text("本地捕获 · 自由开源").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20).frame(width: 220).foregroundStyle(.white)
        .background(IceTheme.ink)
    }

    private func navigation(_ page: String, _ title: String, _ icon: String, count: Int? = nil) -> some View {
        Button { model.selectedPage = page } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 20)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                if let count { Text("\(count)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: Capsule()) }
            }.padding(.horizontal, 12).padding(.vertical, 12)
                .background(model.selectedPage == page ? .white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("完成系统授权，开始使用", systemImage: "lock.open")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 12) {
                if !model.screenPermission { Button("允许屏幕录制") { model.requestScreenPermission() } }
                if !model.accessibilityPermission { Button("允许辅助功能") { model.requestAccessibility() } }
                Button("重新检查") { model.checkPermissions(); Task { await model.catalog.refresh() } }
            }.font(.system(size: 11))
            Text("屏幕录制用于窗口画面；辅助功能用于全局快捷键和定位来源窗口。授权后如系统提示，请重新启动应用。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.88, green: 0.95, blue: 0.97))
    }
}

private struct PageHeader: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 27, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(.bottom, 22)
    }
}

struct WindowList: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var catalog: WindowCatalog
    @State private var search = ""

    private var filtered: [SCWindow] {
        catalog.windows.filter {
            search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search)
                || ($0.owningApplication?.applicationName ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PageHeader(title: "把重要的画面留在眼前", detail: "选择一个窗口，在任何桌面空间中持续关注。")
                Spacer()
                Button { Task { await catalog.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(catalog.loading).help("刷新窗口列表")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用或窗口标题", text: $search).textFieldStyle(.plain)
                if catalog.loading { ProgressView().controlSize(.small) }
            }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10)).padding(.bottom, 18)
            if let error = catalog.error {
                ContentUnavailableView("暂时无法读取窗口", systemImage: "rectangle.badge.exclamationmark", description: Text(error))
            } else if filtered.isEmpty && !catalog.loading {
                ContentUnavailableView(search.isEmpty ? "等待一个窗口" : "没有匹配结果", systemImage: "macwindow",
                                       description: Text(search.isEmpty ? "打开需要关注的应用，然后刷新列表。" : "尝试其他应用名称或标题。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered, id: \.windowID) { source in
                            WindowRow(source: source, active: model.sessions.contains { $0.source.windowID == source.windowID },
                                      capture: { model.start(source) }, region: { model.selectRegion(source) })
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            HStack {
                Text("\(filtered.count) 个窗口").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("快捷捕获  \(model.settings.value.shortcut.display)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(IceTheme.accent)
            }
        }.padding(28).task { await catalog.refresh() }
    }
}

private struct WindowRow: View {
    let source: SCWindow
    let active: Bool
    let capture: () -> Void
    let region: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            if let pid = source.owningApplication?.processID, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
            } else { Image(systemName: "macwindow").font(.title2).frame(width: 32) }
            VStack(alignment: .leading, spacing: 4) {
                Text(source.title?.isEmpty == false ? source.title! : "未命名窗口")
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(source.owningApplication?.applicationName ?? "Application")  ·  #\(source.windowID)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Button(action: region) { Image(systemName: "crop") }.help("选择捕获区域")
            Button(active ? "显示" : "悬浮", action: capture).buttonStyle(.borderedProminent).controlSize(.small)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SessionList: View {
    @ObservedObject var model: ApplicationModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                PageHeader(title: "正在关注", detail: "每个窗口独立控制，帧率按应用记忆。")
                Spacer()
                if !model.sessions.isEmpty { Button("全部关闭") { model.closeAll() }.controlSize(.small) }
            }
            if model.sessions.isEmpty {
                ContentUnavailableView("还没有浮窗", systemImage: "square.on.square",
                                       description: Text("从「选择窗口」添加，或者使用全局快捷键。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.sessions) { SessionCard(session: $0) }
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(28)
    }
}

private struct SessionCard: View {
    @ObservedObject var session: CaptureSession
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(session.idle ? .orange : IceTheme.accent).frame(width: 8, height: 8)
                Text(session.appName).font(.system(size: 11, weight: .semibold)).foregroundStyle(IceTheme.accent)
                Spacer()
                Button { session.close() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭浮窗")
            }
            Text(session.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
            Text(session.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 10) {
                Button(session.paused ? "继续" : "暂停") { session.togglePaused() }
                Button(session.hidden ? "显示" : "隐藏") { session.toggleHidden() }
                Button("定位") { session.focusSource() }
                Menu("\(session.fps) FPS") {
                    ForEach(Preferences.frameRates, id: \.self) { rate in
                        Button("\(rate) FPS") { session.onFrameRate?(session.bundleID, rate) }
                    }
                }.frame(width: 90)
                Spacer()
            }.controlSize(.small)
            HStack(spacing: 15) {
                Toggle("自动隐藏", isOn: $session.autoHide)
                Toggle("空闲提醒", isOn: $session.idleDetection)
                Toggle("图像增强", isOn: $session.enhanced)
            }.toggleStyle(.checkbox).font(.system(size: 11))
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SettingsView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var store: SettingsStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "让它适合你的工作方式", detail: "轻量运行，所有设置保存在这台 Mac 上。")
                group("捕获方式") {
                    Toggle("允许同时关注多个窗口", isOn: $store.value.multiWindow)
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("全局快捷键")
                            Text("额外按住 Shift 可选择区域").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShortcutRecorder(shortcut: $store.value.shortcut, monitor: model.hotkeys)
                            .frame(width: 155, height: 32)
                    }
                    if !model.hotkeysActive {
                        Text("全局按键尚未启用，请检查辅助功能授权；系统必要时还会要求输入监控授权。")
                            .font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
                group("新浮窗的默认设置") {
                    HStack {
                        Text("默认帧率")
                        Spacer()
                        Picker("默认帧率", selection: $store.value.defaultFPS) {
                            ForEach(Preferences.frameRates, id: \.self) { Text("\($0) FPS").tag($0) }
                        }.labelsHidden().frame(width: 110)
                    }
                    Text("日志或进度推荐 1–5 FPS，视频推荐 30–60 FPS。单独设置过的应用保持其帧率。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Divider()
                    Toggle("鼠标移入时隐藏浮窗并暂停捕获", isOn: $store.value.autoHide)
                    Toggle("增强对比度和清晰度", isOn: $store.value.enhanceContrast)
                    Toggle("检测内容空闲", isOn: $store.value.idleDetection)
                    HStack {
                        Text("空闲提醒等待")
                        Spacer()
                        Picker("空闲提醒等待", selection: $store.value.idleSeconds) {
                            ForEach([5.0, 10, 20, 30, 60, 120], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                        }.labelsHidden().frame(width: 110)
                    }
                }
                if !store.value.appFrameRates.isEmpty {
                    group("应用帧率") {
                        ForEach(store.value.appFrameRates.keys.sorted(), id: \.self) { app in
                            HStack {
                                Text(app).font(.system(size: 11)).lineLimit(1)
                                Spacer()
                                Text("\(store.value.appFrameRates[app]!) FPS").font(.system(size: 11, design: .monospaced))
                                Button("清除") {
                                    store.value.appFrameRates.removeValue(forKey: app)
                                    model.sessions.filter { $0.bundleID == app }.forEach { $0.setFPS(store.value.defaultFPS) }
                                }.controlSize(.mini)
                            }
                        }
                    }
                }
                group("启动") {
                    Toggle("登录 Mac 时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLaunchAtLogin($0) }))
                    Text("IceScreen 关闭控制中心后会继续在菜单栏运行。")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text("IceScreen 1.0.0 · GPL-3.0-or-later").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(28)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(IceTheme.accent)
            content().font(.system(size: 12))
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct GuideView: View {
    let shortcut: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "少一点切换，多一点专注", detail: "将鼠标移到浮窗上，即可使用下列操作。")
                VStack(spacing: 0) {
                    row(shortcut, "捕获当前窗口")
                    row("Shift + \(shortcut)", "选择当前窗口中的区域")
                    row("fn + 双击来源窗口", "快速捕获鼠标附近区域")
                    row("双击浮窗", "定位来源窗口")
                    row("⌘ + 拖动", "放大选中的区域")
                    row("⌘ + 双击", "恢复完整画面")
                    row("滚动 / ⌘ + 滚动", "平移 / 缩放")
                    row("= / −", "放大 / 缩小")
                    row("F / D", "切换帧率 / 空闲提醒")
                    row("轻按 fn", "隐藏或恢复浮窗")
                    row("Delete", "关闭浮窗")
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                Text("手动隐藏的浮窗在 60 秒后自动关闭。自动隐藏的浮窗在鼠标离开后恢复。macOS 可在系统设置 → 键盘中将 fn / 地球键设为「不执行操作」，避免触发系统动作。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("命令行").font(.system(size: 15, weight: .semibold))
                Text("/Applications/IceScreen.app/Contents/MacOS/IceScreen --app Terminal --zoom bottom-left:3x")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(IceTheme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }.padding(28)
        }
    }
    private func row(_ key: String, _ detail: String) -> some View {
        HStack {
            Text(key).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(IceTheme.accent)
            Spacer()
            Text(detail).font(.system(size: 11))
        }.padding(.vertical, 9)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    let monitor: HotkeyMonitor
    func makeNSView(context: Context) -> ShortcutButton {
        let button = ShortcutButton()
        button.onRecord = { shortcut = $0 }
        button.onRecording = { monitor.recording = $0 }
        return button
    }
    func updateNSView(_ view: ShortcutButton, context: Context) {
        if !view.recording { view.title = shortcut.display }
        view.savedTitle = shortcut.display
    }
}

final class ShortcutButton: NSButton {
    var onRecord: ((Shortcut) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var savedTitle = ""
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self; action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func beginRecording() {
        recording = true
        onRecording?(true)
        title = "按下组合键 · Esc 取消"
        window?.makeFirstResponder(self)
    }
    override func resignFirstResponder() -> Bool {
        recording = false; onRecording?(false); title = savedTitle
        return super.resignFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { window?.makeFirstResponder(nil); return }
        let flags = event.modifierFlags
        guard !flags.contains(.shift), !flags.intersection([.command, .control, .option, .function]).isEmpty else {
            title = "需要修饰键，保留 Shift"; return
        }
        let label = event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        let value = Shortcut(keyCode: event.keyCode, command: flags.contains(.command), option: flags.contains(.option),
                             control: flags.contains(.control), function: flags.contains(.function), label: label)
        savedTitle = value.display
        onRecord?(value)
        window?.makeFirstResponder(nil)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
#endif
