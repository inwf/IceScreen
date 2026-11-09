#if os(macOS)
import AppKit
import SwiftUI
import IceCore

struct SettingsView: View {
    let model: ApplicationModel
    @ObservedObject var store: SettingsStore
    @State private var selection: SettingsPage? = .general
    @State private var screenPermission = false
    @State private var accessibilityPermission = false
    @State private var hotkeysActive = false
    @State private var loginEnabled = false
    @State private var displayedError: String?
    private var page: SettingsPage { selection ?? .general }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("偏好设置") {
                    ForEach(SettingsPage.allCases.filter { $0 != .about }) { item in
                        Label(item.title, systemImage: item.icon)
                            .tag(item)
                    }
                }
                Section {
                    Label(SettingsPage.about.title, systemImage: SettingsPage.about.icon).tag(SettingsPage.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Group {
                    switch page {
                    case .general: general
                    case .floatingWindows: floatingWindows
                    case .appearance: AppearanceSettings(store: store)
                    case .detection: detection
                    case .media: media
                    case .keyboard: keyboard
                    case .about: about
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.identity)
                .animation(nil, value: page)
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(page.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minHeight: 540, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(model.$screenPermission.removeDuplicates()) { screenPermission = $0 }
        .onReceive(model.$accessibilityPermission.removeDuplicates()) { accessibilityPermission = $0 }
        .onReceive(model.$hotkeysActive.removeDuplicates()) { hotkeysActive = $0 }
        .onReceive(model.$loginEnabled.removeDuplicates()) { loginEnabled = $0 }
        .onReceive(model.$error.removeDuplicates()) { displayedError = $0 }
        .alert("IceScreen", isPresented: Binding(get: { displayedError != nil }, set: {
            if !$0 { displayedError = nil; model.error = nil }
        })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(displayedError ?? "") }
    }

    private var general: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动 IceScreen", isOn: Binding(get: { loginEnabled }, set: model.setLaunchAtLogin))
                Toggle("显示菜单栏图标", isOn: $store.value.showMenuBarIcon)
                Text("隐藏图标后仍会继续运行。再次打开 IceScreen 可以回到设置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("系统权限") {
                permissionRow("屏幕录制", granted: screenPermission, action: model.requestScreenPermission)
                permissionRow("辅助功能", granted: accessibilityPermission, action: model.requestAccessibility)
                if !hotkeysActive && accessibilityPermission {
                    Label("全局按键尚未启用，请检查系统的输入监控权限。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("重新检查权限") { model.checkPermissions() }
            }
        }.formStyle(.grouped)
    }

    private var floatingWindows: some View {
        Form {
            Section("显示与位置") {
                Toggle("多窗口模式", isOn: $store.value.multiWindow)
                Toggle("快速捕获时智能识别局部边界", isOn: $store.value.smartRegionCapture)
                Text("识别鼠标所在的图片、视频或内容区域，并裁去对称黑白边框。没有合适边界时放大鼠标附近的区域。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("出现位置", selection: $store.value.panelPosition) {
                    ForEach(ZoomAnchor.allCases, id: \.self) { Text(positionName($0)).tag($0) }
                }
                Toggle("显示在全屏桌面空间", isOn: $store.value.showOnFullscreenSpaces)
            }
            Section("来源窗口与预览") {
                Toggle("单击定位来源窗口并保留浮窗", isOn: $store.value.clickToFocus)
                Toggle("捕获后自动移走来源窗口", isOn: $store.value.moveSourceOffscreen)
                Text("单击浮窗返回来源，再次单击将来源移走。双击返回并关闭浮窗。关闭浮窗或退出时恢复来源位置；全屏和无法移动的窗口保持原位。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("来源窗口获得焦点时", selection: $store.value.sourceFocusBehavior) {
                    Text("保持浮窗").tag(SourceFocusBehavior.keep)
                    Text("暂停捕获").tag(SourceFocusBehavior.pause)
                    Text("关闭浮窗").tag(SourceFocusBehavior.close)
                }
                Toggle("Space 预览来源窗口", isOn: $store.value.quickLook)
            }
            frameRateSettings
        }.formStyle(.grouped)
    }

    private var frameRateSettings: some View {
        Group {
            Section {
                Picker("默认帧率", selection: $store.value.defaultFPS) {
                    ForEach(Preferences.frameRates, id: \.self) { Text("\($0) FPS").tag($0) }
                }
            } header: { Text("画面与性能") } footer: {
                Text("默认 10 FPS。静态进度可用 1 FPS，视频可用 30 或 60 FPS。悬停时按 F 打开帧率菜单，选择会按应用保存。")
            }
            if !store.value.appFrameRates.isEmpty {
                Section("应用帧率") {
                    ForEach(store.value.appFrameRates.keys.sorted(), id: \.self) { app in
                        HStack {
                            Text(app).lineLimit(1)
                            Spacer()
                            Text("\(store.value.appFrameRates[app]!) FPS").foregroundStyle(.secondary)
                            Button("重置") {
                                store.value.appFrameRates.removeValue(forKey: app)
                                model.sessions.filter { $0.bundleID == app }.forEach { $0.setFPS(store.value.defaultFPS) }
                            }.controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var media: some View {
        Form {
            Section("播放控制") {
                Toggle("显示来源媒体的播放控制", isOn: $store.value.mediaControls)
                Toggle("显示进度条并允许调整进度", isOn: $store.value.mediaSeek).disabled(!store.value.mediaControls)
                Toggle("轻按 Space 播放或暂停", isOn: $store.value.mediaSpace).disabled(!store.value.mediaControls)
                Text("鼠标悬停浮窗时显示播放、暂停、上一首和下一首。媒体需要向系统提供播放状态；直播或禁止跳转的内容不显示进度条。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Music、TV、Spotify、Swinsian 和 VLC 的进度通过应用自动化调整，首次使用时请允许系统的自动化请求。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("快捷操作") {
                LabeledContent("轻按 Space", value: "播放或暂停")
                LabeledContent("长按 Space", value: "预览来源窗口，松开关闭")
                LabeledContent("← / →", value: "后退 / 前进 5 秒")
                Text("长按预览遵循“浮窗”页面的 Space 预览开关。未识别到媒体的浮窗继续使用原有的 Space 预览操作。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var detection: some View {
        Form {
            Section {
                Toggle("检测内容空闲", isOn: $store.value.idleDetection)
                Picker("保持静止多久后提醒", selection: $store.value.idleSeconds) {
                    ForEach([5.0, 10, 20, 30, 60, 120], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                }.disabled(!store.value.idleDetection)
                Toggle("检测画面变化", isOn: $store.value.changeDetection)
                Picker("变化检测前的安静时间", selection: $store.value.changeSeconds) {
                    ForEach([1.0, 5, 10, 20, 30, 60, 120], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                }.disabled(!store.value.changeDetection)
                Toggle("检测细微变化", isOn: $store.value.sensitiveDetection)
            } header: { Text("检测条件") } footer: {
                Text("空闲检测会在画面停止变化时提醒；变化检测会在画面安静一段时间后重新出现变化时提醒。细微变化适用于进度条和加载指示器。悬停时使用 D、C、S 分别切换。")
            }
            Section {
                Toggle("发送系统通知", isOn: $store.value.detectionNotifications)
                Text("点击通知可以定位来源窗口。隐藏、暂停和睡眠期间停止检测，恢复捕获后重新开始计时。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("提醒") }
            Section("自动化") {
                DisclosureGroup("运行 Shell 命令") {
                    TextField("Shell 命令（留空时关闭）", text: $store.value.detectionCommand, axis: .vertical)
                        .font(.system(.body, design: .monospaced)).lineLimit(3...6)
                    Picker("执行超时", selection: $store.value.detectionCommandTimeout) {
                        ForEach([5.0, 15, 30, 60, 120, 300], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                    }
                    Text("通过 /bin/sh 执行。提供 ICESCREEN_EVENT（idle/change）、ICESCREEN_APP、ICESCREEN_BUNDLE_ID、ICESCREEN_WINDOW_ID 和 ICESCREEN_WINDOW_TITLE 环境变量。每个浮窗同时运行一个命令；执行期间忽略新的命令触发。超时或关闭浮窗会终止命令进程组。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }

    private var keyboard: some View {
        Form {
            Section {
                shortcutRow("捕获当前窗口", shortcut: $store.value.shortcut, action: .capture)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("捕获窗口区域")
                        Text(store.value.regionShortcut == nil ? "自动添加一个未使用的修饰键" : "独立快捷键")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(shortcut: Binding(
                        get: { store.value.effectiveRegionShortcut ?? Shortcut(shift: true) },
                        set: { store.value.regionShortcut = $0 }), monitor: model.hotkeys,
                        validate: { store.value.shortcutConflict($0, for: .region) })
                        .frame(width: 160, height: 28)
                    if store.value.regionShortcut != nil {
                        Button("自动") {
                            if let candidate = store.value.shortcut.regionVariant,
                               let issue = store.value.shortcutConflict(candidate, for: .region) { model.error = issue }
                            else { store.value.regionShortcut = nil }
                        }.controlSize(.small)
                    }
                }
                Toggle("关闭所有浮窗快捷键", isOn: Binding(get: { store.value.closeAllShortcut != nil }, set: {
                    let candidate = Shortcut(keyCode: 35, command: true, function: false, shift: true, label: "P")
                    if $0, let issue = store.value.shortcutConflict(candidate, for: .closeAll) { model.error = issue }
                    else { store.value.closeAllShortcut = $0 ? candidate : nil }
                }))
                if store.value.closeAllShortcut != nil {
                    shortcutRow("全部关闭", shortcut: Binding(get: { store.value.closeAllShortcut! }, set: { store.value.closeAllShortcut = $0 }), action: .closeAll)
                }
                Button("恢复默认快捷键") {
                    store.value.shortcut = Shortcut()
                    store.value.regionShortcut = nil
                    store.value.closeAllShortcut = nil
                }.controlSize(.small)
            } header: { Text("全局快捷键") } footer: {
                Text("支持 ⌘、⌥、⌃、⇧ 和 fn 组合。例如 ⌘⇧I；其自动区域快捷键为 ⌥⇧⌘I。")
            }
            Section {
                Picker("触发修饰键", selection: $store.value.triggerModifier) {
                    ForEach(TriggerModifier.allCases, id: \.self) { Text($0.display).tag($0) }
                }
                Toggle("按住修饰键并双击来源窗口，快速捕获局部区域", isOn: $store.value.quickRegionCapture)
            } header: { Text("修饰键手势") } footer: {
                Text("轻按 \(store.value.triggerModifier.display) 隐藏或恢复浮窗，双击切换自动隐藏。系统设置 → 键盘可将 fn / 地球键设为「不执行操作」。")
            }
            Section {
                DisclosureGroup("查看浮窗操作速查") {
                    instruction("轻按 \(store.value.triggerModifier.display)", "隐藏 / 恢复浮窗")
                    instruction("双击 \(store.value.triggerModifier.display)", "切换自动隐藏")
                    instruction("Space", "预览来源窗口；长按松开关闭")
                    instruction("Delete", "关闭浮窗（透明时也有效）")
                    instruction("F", "打开应用帧率菜单")
                    instruction("D", "切换内容空闲检测")
                    instruction("C", "切换画面变化检测")
                    instruction("S", "切换细微变化检测")
                    instruction("双击", "定位来源窗口并关闭浮窗")
                    instruction("单击", store.value.clickToFocus ? "定位来源窗口并保留浮窗" : "单击定位已关闭，可在「浮窗」中开启")
                    instruction("⌘ + 拖动", "框选缩放区域")
                    instruction("⌘ + 双击", "恢复完整画面")
                    instruction("0", "恢复完整画面")
                    instruction("滚动 / ⌘ + 滚动", "平移 / 缩放")
                    instruction("捏合 / = / −", "缩放画面")
                }
            } footer: { Text("以上操作在鼠标位于浮窗上时生效。手动隐藏 60 秒后自动关闭。") }
        }.formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("IceScreen").font(.largeTitle.weight(.semibold))
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建")
                    .foregroundStyle(.secondary)
            }
            Text("让你关注的窗口，留在眼前。")
            Text("happy · 好朋友")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 4) {
                Text("Copyright © 2026 IceScreen contributors")
                Text("GPL-3.0-or-later")
            }.font(.caption2).foregroundStyle(.tertiary)
        }.padding(30).frame(maxWidth: .infinity)
    }

    private func shortcutRow(_ title: String, shortcut: Binding<Shortcut>, action: ShortcutAction) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(shortcut: shortcut, monitor: model.hotkeys,
                             validate: { store.value.shortcutConflict($0, for: action) }).frame(width: 160, height: 28)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted { Label("已允许", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Button("允许…", action: action) }
        }
    }

    private func instruction(_ key: String, _ detail: String) -> some View {
        LabeledContent(detail) { Text(key).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
    }

    private func positionName(_ anchor: ZoomAnchor) -> String {
        switch anchor {
        case .topLeft: return "左上"; case .top: return "上方"; case .topRight: return "右上"
        case .left: return "左侧"; case .center: return "居中"; case .right: return "右侧"
        case .bottomLeft: return "左下"; case .bottom: return "下方"; case .bottomRight: return "右下"
        }
    }
}

private enum SettingsPage: CaseIterable, Hashable, Identifiable {
    case general, keyboard, floatingWindows, appearance, media, detection, about
    var id: Self { self }
    var title: String {
        switch self {
        case .general: return "通用"
        case .floatingWindows: return "浮窗"
        case .appearance: return "外观"
        case .media: return "媒体"
        case .detection: return "检测与自动化"
        case .keyboard: return "快捷键"
        case .about: return "关于"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .floatingWindows: return "pip"
        case .appearance: return "rectangle.on.rectangle.angled"
        case .media: return "playpause"
        case .detection: return "waveform.path"
        case .keyboard: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    let monitor: HotkeyMonitor
    let validate: (Shortcut) -> String?
    func makeNSView(context: Context) -> ShortcutButton { ShortcutButton(frame: .zero) }
    func updateNSView(_ view: ShortcutButton, context: Context) {
        if !view.recording { view.title = shortcut.display }
        view.savedTitle = shortcut.display
        view.onRecord = { shortcut = $0 }
        view.validate = validate
        view.onRecording = { monitor.recording = $0 }
    }
    static func dismantleNSView(_ view: ShortcutButton, coordinator: ()) { view.finishRecording() }
}

final class ShortcutButton: NSButton {
    var onRecord: ((Shortcut) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var validate: ((Shortcut) -> String?)?
    var savedTitle = ""
    private(set) var recording = false
    private var eventMonitor: Any?
    private var observer: NSObjectProtocol?
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self; action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    @objc private func beginRecording() {
        if recording { finishRecording(); return }
        window?.makeFirstResponder(self)
        recording = true
        onRecording?(true)
        title = "按下快捷键 · Esc 取消"
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recording else { return event }
            self.capture(event)
            return nil
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishRecording() }
        }
    }

    func finishRecording() {
        recording = false
        onRecording?(false)
        title = savedTitle
        toolTip = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }

    override func resignFirstResponder() -> Bool { finishRecording(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        if recording { capture(event) } else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        capture(event); return true
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { finishRecording(); return }
        let flags = event.modifierFlags
        guard !flags.intersection([.command, .control, .option, .function, .shift]).isEmpty else {
            title = "请同时按住修饰键"; return
        }
        let label: String
        switch event.keyCode {
        case 49: label = "Space"; case 36: label = "Return"; case 48: label = "Tab"; case 51: label = "Delete"
        default: label = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        let value = Shortcut(keyCode: event.keyCode, command: flags.contains(.command), option: flags.contains(.option),
                             control: flags.contains(.control), function: flags.contains(.function), shift: flags.contains(.shift), label: label)
        if let issue = validate?(value) { title = "快捷键冲突，请重新输入"; toolTip = issue; NSSound.beep(); return }
        savedTitle = value.display
        onRecord?(value)
        finishRecording()
    }
}
#endif
