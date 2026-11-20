#if os(macOS)
import AppKit
import SwiftUI
import IceCore

struct SettingsView: View {
    let model: ApplicationModel
    @ObservedObject var store: SettingsStore
    @ObservedObject var state: SettingsWindowState
    @State private var screenPermission = false
    @State private var accessibilityPermission = false
    @State private var hotkeysActive = false
    @State private var loginEnabled = false
    @State private var displayedError: String?
    private var page: SettingsPage { state.selection ?? .general }

    var body: some View {
        let language = store.value.language
        NavigationSplitView {
            List(selection: $state.selection) {
                Section(L10n.text("偏好设置", "Preferences", language: language)) {
                    ForEach(SettingsPage.allCases.filter { $0 != .about }) { item in
                        Label(item.title(in: language), systemImage: item.icon)
                            .tag(item)
                    }
                }
                Section {
                    Label(SettingsPage.about.title(in: language), systemImage: SettingsPage.about.icon).tag(SettingsPage.about)
                }
            }
            .listStyle(.sidebar)
            // AppKit can retain sidebar row views across language changes. Keep the selection in window state.
            .id(language)
            .navigationSplitViewColumnWidth(min: language == .english ? 210 : 180,
                                            ideal: language == .english ? 220 : 200, max: 240)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Group {
                    switch page {
                    case .general: general
                    case .floatingWindows: floatingWindows
                    case .appearance: AppearanceSettings(store: store, images: state.images, showOriginal: $state.showOriginal)
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
            .navigationTitle(page.title(in: language))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minHeight: 540, idealHeight: 640)
        .background {
            if #unavailable(macOS 26.0) {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .environment(\.locale, language.locale)
        .onReceive(model.$screenPermission.removeDuplicates()) { screenPermission = $0 }
        .onReceive(model.$accessibilityPermission.removeDuplicates()) { accessibilityPermission = $0 }
        .onReceive(model.$hotkeysActive.removeDuplicates()) { hotkeysActive = $0 }
        .onReceive(model.$loginEnabled.removeDuplicates()) { loginEnabled = $0 }
        .onReceive(model.$error.removeDuplicates()) { displayedError = $0 }
        .alert("IceScreen", isPresented: Binding(get: { displayedError != nil }, set: {
            if !$0 { displayedError = nil; model.error = nil }
        })) {
            Button(L10n.text("好", "OK"), role: .cancel) { model.error = nil }
        } message: { Text(displayedError ?? "") }
    }

    private var general: some View {
        Form {
            Section(L10n.text("语言", "Language")) {
                Picker(L10n.text("界面语言", "App language"), selection: $store.value.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .accessibilityIdentifier("settings.language")
                Text(L10n.text("切换后立即生效。", "Changes take effect immediately."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("启动", "Startup")) {
                Toggle(L10n.text("登录时启动 IceScreen", "Launch IceScreen at login"), isOn: Binding(get: { loginEnabled }, set: model.setLaunchAtLogin))
                Toggle(L10n.text("显示菜单栏图标", "Show menu bar icon"), isOn: $store.value.showMenuBarIcon)
                Text(L10n.text("隐藏图标后仍会继续运行。再次打开 IceScreen 可以回到设置。", "IceScreen keeps running when the icon is hidden. Open the app again to access settings."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("系统权限", "System permissions")) {
                permissionRow(L10n.text("屏幕录制", "Screen Recording"), granted: screenPermission, action: model.requestScreenPermission)
                permissionRow(L10n.text("辅助功能", "Accessibility"), granted: accessibilityPermission, action: model.requestAccessibility)
                if !hotkeysActive && accessibilityPermission {
                    Label(L10n.text("全局按键尚未启用，请检查系统的输入监控权限。", "Global shortcuts are unavailable. Check Input Monitoring permission in System Settings."), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(L10n.text("重新检查权限", "Check permissions again")) { model.checkPermissions() }
            }
        }.formStyle(.grouped)
    }

    private var floatingWindows: some View {
        let language = store.value.language
        return Form {
            Section(L10n.text("显示与位置", "Display and position")) {
                Toggle(L10n.text("多窗口模式", "Allow multiple panels"), isOn: $store.value.multiWindow)
                Toggle(L10n.text("快速捕获时智能识别局部边界", "Detect content boundaries during quick capture"), isOn: $store.value.smartRegionCapture)
                Text(L10n.text("识别鼠标所在的图片、视频或内容区域，并裁去对称黑白边框。没有合适边界时放大鼠标附近的区域。", "Detect the image, video, or content under the pointer and crop symmetric black or white borders. If no boundary is found, zoom into the area around the pointer."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L10n.text("出现位置", "Initial position"), selection: $store.value.panelPosition) {
                    ForEach(ZoomAnchor.allCases, id: \.self) { Text(positionName($0, language: language)).tag($0) }
                }
                Toggle(L10n.text("显示在全屏桌面空间", "Show in full-screen Spaces"), isOn: $store.value.showOnFullscreenSpaces)
            }
            Section(L10n.text("来源窗口与预览", "Source window and preview")) {
                Toggle(L10n.text("单击切换来源与上一个窗口", "Click to switch between the source and previous window"), isOn: $store.value.clickToFocus)
                Text(L10n.text("单击浮窗聚焦来源窗口，再单击同一浮窗回到刚才使用的窗口。双击聚焦来源并关闭浮窗。", "Click a panel to focus its source. Click it again to return to your previous window. Double-click to focus the source and close the panel."))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L10n.text("来源窗口获得焦点时", "When the source gains focus"), selection: $store.value.sourceFocusBehavior) {
                    Text(L10n.text("保持浮窗", "Keep panel")).tag(SourceFocusBehavior.keep)
                    Text(L10n.text("暂停捕获", "Pause capture")).tag(SourceFocusBehavior.pause)
                    Text(L10n.text("关闭浮窗", "Close panel")).tag(SourceFocusBehavior.close)
                }
                Toggle(L10n.text("Space 预览来源窗口", "Preview source with Space"), isOn: $store.value.quickLook)
            }
            frameRateSettings
        }.formStyle(.grouped)
    }

    private var frameRateSettings: some View {
        let language = store.value.language
        return Group {
            Section {
                Picker(L10n.text("默认帧率", "Default frame rate"), selection: $store.value.defaultFPS) {
                    ForEach(Preferences.frameRates, id: \.self) { Text("\($0) FPS").tag($0) }
                }
            } header: { Text(L10n.text("画面与性能", "Capture and performance")) } footer: {
                Text(L10n.text("默认 10 FPS。静态进度可用 1 FPS，视频可用 30 或 60 FPS。悬停时按 F 打开帧率菜单，选择会按应用保存。", "The default is 10 FPS. Use 1 FPS for static progress or 30–60 FPS for video. Hover and press F to choose a frame rate, saved per app."))
            }
            if !store.value.appFrameRates.isEmpty {
                Section(L10n.text("应用帧率", "Frame rates by app")) {
                    ForEach(store.value.appFrameRates.keys.sorted(), id: \.self) { app in
                        HStack {
                            Text(app).lineLimit(1)
                            Spacer()
                            Text("\(store.value.appFrameRates[app]!) FPS").foregroundStyle(.secondary)
                            Button(L10n.text("重置", "Reset", language: language)) {
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
            Section(L10n.text("播放控制", "Playback controls")) {
                Toggle(L10n.text("显示来源媒体的播放控制", "Show source media controls"), isOn: $store.value.mediaControls)
                Toggle(L10n.text("显示进度条并允许调整进度", "Show playback progress and allow seeking"), isOn: $store.value.mediaSeek).disabled(!store.value.mediaControls)
                Toggle(L10n.text("轻按 Space 播放或暂停", "Tap Space to play or pause"), isOn: $store.value.mediaSpace).disabled(!store.value.mediaControls)
                Text(L10n.text("鼠标悬停浮窗时显示播放、暂停、上一首和下一首。媒体需要向系统提供播放状态；直播或禁止跳转的内容不显示进度条。", "Hover to show playback and track controls. The source must provide system media information. Live streams and media that cannot seek have no progress slider."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("Music、TV、Spotify、Swinsian 和 VLC 的进度通过应用自动化调整，首次使用时请允许系统的自动化请求。", "Seeking in Music, TV, Spotify, Swinsian, and VLC uses app automation. Allow the system automation request on first use."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("快捷操作", "Quick actions")) {
                LabeledContent(L10n.text("轻按 Space", "Tap Space"), value: L10n.text("播放或暂停", "Play or pause"))
                LabeledContent(L10n.text("长按 Space", "Hold Space"), value: L10n.text("预览来源窗口，松开关闭", "Preview source; release to close"))
                LabeledContent("← / →", value: L10n.text("后退 / 前进 5 秒", "Back / forward 5 seconds"))
                Text(L10n.text("长按预览遵循“浮窗”页面的 Space 预览开关。未识别到媒体的浮窗继续使用原有的 Space 预览操作。", "Hold-to-preview follows the Space preview setting under Panels. Panels without recognized media keep the usual Space preview behavior."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var detection: some View {
        let language = store.value.language
        return Form {
            Section {
                Toggle(L10n.text("检测内容空闲", "Detect idle content"), isOn: $store.value.idleDetection)
                Picker(L10n.text("保持静止多久后提醒", "Notify after idle for"), selection: $store.value.idleSeconds) {
                    ForEach([5.0, 10, 20, 30, 60, 120], id: \.self) { Text(L10n.text("\(Int($0)) 秒", "\(Int($0)) seconds", language: language)).tag($0) }
                }.disabled(!store.value.idleDetection)
                Toggle(L10n.text("检测画面变化", "Detect content changes"), isOn: $store.value.changeDetection)
                Picker(L10n.text("变化检测前的安静时间", "Quiet time before detecting changes"), selection: $store.value.changeSeconds) {
                    ForEach([1.0, 5, 10, 20, 30, 60, 120], id: \.self) { Text(L10n.text("\(Int($0)) 秒", "\(Int($0)) seconds", language: language)).tag($0) }
                }.disabled(!store.value.changeDetection)
                Toggle(L10n.text("检测细微变化", "Detect subtle changes"), isOn: $store.value.sensitiveDetection)
            } header: { Text(L10n.text("检测条件", "Detection rules")) } footer: {
                Text(L10n.text("空闲检测会在画面停止变化时提醒；变化检测会在画面安静一段时间后重新出现变化时提醒。细微变化适用于进度条和加载指示器。悬停时使用 D、C、S 分别切换。", "Idle detection notifies you when content stops changing. Change detection notifies you when changes resume after a quiet period. Subtle detection suits progress bars and loading indicators. Hover and press D, C, or S to toggle each mode."))
            }
            Section {
                Toggle(L10n.text("发送系统通知", "Send system notifications"), isOn: $store.value.detectionNotifications)
                Text(L10n.text("点击通知可以定位来源窗口。隐藏、暂停和睡眠期间停止检测，恢复捕获后重新开始计时。", "Click a notification to focus the source window. Detection stops while hidden, paused, or asleep and restarts its timer when capture resumes."))
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text(L10n.text("提醒", "Notifications")) }
            Section(L10n.text("自动化", "Automation")) {
                DisclosureGroup(L10n.text("运行 Shell 命令", "Run a shell command")) {
                    TextField(L10n.text("Shell 命令（留空时关闭）", "Shell command (leave empty to disable)"), text: $store.value.detectionCommand, axis: .vertical)
                        .font(.system(.body, design: .monospaced)).lineLimit(3...6)
                    Picker(L10n.text("执行超时", "Execution timeout"), selection: $store.value.detectionCommandTimeout) {
                        ForEach([5.0, 15, 30, 60, 120, 300], id: \.self) { Text(L10n.text("\(Int($0)) 秒", "\(Int($0)) seconds", language: language)).tag($0) }
                    }
                    Text(L10n.text("通过 /bin/sh 执行。提供 ICESCREEN_EVENT（idle/change）、ICESCREEN_APP、ICESCREEN_BUNDLE_ID、ICESCREEN_WINDOW_ID 和 ICESCREEN_WINDOW_TITLE 环境变量。每个浮窗同时运行一个命令；执行期间忽略新的命令触发。超时或关闭浮窗会终止命令进程组。", "Runs through /bin/sh with ICESCREEN_EVENT (idle/change), ICESCREEN_APP, ICESCREEN_BUNDLE_ID, ICESCREEN_WINDOW_ID, and ICESCREEN_WINDOW_TITLE environment variables. Each panel runs one command at a time and ignores new triggers while it runs. A timeout or closing the panel terminates the command process group."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.formStyle(.grouped)
    }

    private var keyboard: some View {
        Form {
            Section {
                shortcutRow(L10n.text("捕获当前窗口", "Capture current window"), shortcut: $store.value.shortcut, action: .capture)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("捕获窗口区域", "Capture window region"))
                        Text(store.value.regionShortcut == nil ? L10n.text("自动添加一个未使用的修饰键", "Automatically add an unused modifier") : L10n.text("独立快捷键", "Custom shortcut"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(shortcut: Binding(
                        get: { store.value.effectiveRegionShortcut ?? Shortcut(shift: true) },
                        set: { store.value.regionShortcut = $0 }), title: L10n.text("捕获窗口区域", "Capture window region"),
                        monitor: model.hotkeys,
                        validate: { store.value.shortcutConflict($0, for: .region) })
                        .frame(width: 160, height: 28)
                    if store.value.regionShortcut != nil {
                        Button(L10n.text("自动", "Automatic")) {
                            if let candidate = store.value.shortcut.regionVariant,
                               let issue = store.value.shortcutConflict(candidate, for: .region) { model.error = issue }
                            else { store.value.regionShortcut = nil }
                        }.controlSize(.small)
                    }
                }
                Toggle(L10n.text("关闭所有浮窗快捷键", "Enable shortcut to close all panels"), isOn: Binding(get: { store.value.closeAllShortcut != nil }, set: {
                    let candidate = Shortcut(keyCode: 35, command: true, function: false, shift: true, label: "P")
                    if $0, let issue = store.value.shortcutConflict(candidate, for: .closeAll) { model.error = issue }
                    else { store.value.closeAllShortcut = $0 ? candidate : nil }
                }))
                if store.value.closeAllShortcut != nil {
                    shortcutRow(L10n.text("全部关闭", "Close all panels"), shortcut: Binding(get: { store.value.closeAllShortcut! }, set: { store.value.closeAllShortcut = $0 }), action: .closeAll)
                }
                Button(L10n.text("恢复默认快捷键", "Restore default shortcuts")) {
                    store.value.shortcut = Shortcut()
                    store.value.regionShortcut = nil
                    store.value.closeAllShortcut = nil
                }.controlSize(.small)
            } header: { Text(L10n.text("全局快捷键", "Global shortcuts")) } footer: {
                Text(L10n.text("支持 ⌘、⌥、⌃、⇧ 和 fn 组合。例如 ⌘⇧I；其自动区域快捷键为 ⌥⇧⌘I。", "Combine ⌘, ⌥, ⌃, ⇧, and fn. For example, ⌘⇧I automatically uses ⌥⇧⌘I for region capture."))
            }
            Section {
                Picker(L10n.text("触发修饰键", "Trigger modifier"), selection: $store.value.triggerModifier) {
                    ForEach(TriggerModifier.allCases, id: \.self) { Text($0.display).tag($0) }
                }
            } header: { Text(L10n.text("修饰键手势", "Modifier gestures")) } footer: {
                Text(L10n.text("在浮窗上双击 \(store.value.triggerModifier.display) 切换所有浮窗的自动隐藏。系统设置 → 键盘可将 fn / 地球键设为「不执行操作」。", "Double-tap \(store.value.triggerModifier.display) over a panel to toggle auto-hide for all panels. In System Settings → Keyboard, set the fn / Globe key to Do Nothing."))
            }
            Section {
                Toggle(L10n.text("快速捕获局部区域", "Enable quick region capture"), isOn: $store.value.quickRegionCapture)
                HStack {
                    Text(L10n.text("捕获手势", "Capture gesture"))
                    Spacer()
                    QuickCaptureRecorder(modifiers: $store.value.quickCaptureModifiers, language: store.value.language, monitor: model.hotkeys)
                        .frame(width: 210, height: 28)
                        .disabled(!store.value.quickRegionCapture)
                }
                Button(L10n.text("恢复默认捕获手势", "Restore default capture gesture")) { store.value.quickCaptureModifiers = .function }
                    .controlSize(.small)
            } header: { Text(L10n.text("快速局部捕获", "Quick region capture")) } footer: {
                Text(L10n.text("点击捕获手势，按住需要的修饰键组合后全部松开保存，例如 ⌘⇧。在来源窗口中按住该组合并双击即可捕获；只有完整匹配的组合才会拦截点击。匹配组合的单击会等待系统双击判定后送达，拖动立即放行。", "Click the gesture, hold your modifier combination (such as ⌘⇧), then release all keys to save. Hold that exact combination and double-click a source window to capture. Matching single clicks wait for the system double-click interval; dragging passes through immediately."))
            }
            Section {
                DisclosureGroup(L10n.text("查看浮窗操作速查", "Panel controls reference")) {
                    instruction(L10n.text("双击 \(store.value.triggerModifier.display)", "Double-tap \(store.value.triggerModifier.display)"), L10n.text("切换自动隐藏", "Toggle auto-hide"))
                    instruction("Space", L10n.text("预览来源窗口；长按松开关闭", "Preview source; release after holding to close"))
                    instruction("Delete", L10n.text("关闭浮窗（透明时也有效）", "Close panel, including when transparent"))
                    instruction("F", L10n.text("打开应用帧率菜单", "Open frame rate menu"))
                    instruction("D", L10n.text("切换内容空闲检测", "Toggle idle detection"))
                    instruction("C", L10n.text("切换画面变化检测", "Toggle change detection"))
                    instruction("S", L10n.text("切换细微变化检测", "Toggle subtle detection"))
                    instruction(L10n.text("双击", "Double-click"), L10n.text("定位来源窗口并关闭浮窗", "Focus source and close panel"))
                    instruction(L10n.text("单击", "Click"), store.value.clickToFocus ? L10n.text("在来源与上一个窗口间切换", "Switch between the source and previous window") : L10n.text("单击切换已关闭，可在「浮窗」中开启", "Click switching is off. Enable it under Panels."))
                    instruction(L10n.text("⌘ + 拖动", "⌘ + drag"), L10n.text("框选缩放区域", "Select region to zoom"))
                    instruction(L10n.text("⌘ + 双击", "⌘ + double-click"), L10n.text("恢复完整画面", "Restore full view"))
                    instruction("0", L10n.text("恢复完整画面", "Restore full view"))
                    instruction(L10n.text("滚动 / ⌘ + 滚动", "Scroll / ⌘ + scroll"), L10n.text("平移 / 缩放", "Pan / zoom"))
                    instruction(L10n.text("捏合 / = / −", "Pinch / = / −"), L10n.text("缩放画面", "Zoom content"))
                }
            } footer: { Text(L10n.text("以上操作在鼠标位于浮窗上时生效。", "These controls work while the pointer is over a panel.")) }
        }.formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            VStack(spacing: 6) {
                Text("IceScreen").font(.largeTitle.weight(.semibold))
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L10n.text("开发构建", "Development build"))
                    .foregroundStyle(.secondary)
            }
            Text(L10n.text("让你关注的窗口，留在眼前。", "Keep the windows you care about in view."))
            Text(verbatim: "happy • 好朋友")
                .font(.caption).foregroundStyle(.secondary)
            Link(L10n.text("GitHub 项目主页", "View on GitHub"), destination: URL(string: "https://github.com/inwf/IceScreen")!)
                .accessibilityIdentifier("about.github")
            Spacer()
            VStack(spacing: 4) {
                Text(L10n.text("版权所有 © 2026 IceScreen 贡献者", "Copyright © 2026 IceScreen contributors"))
                Text("GPL-3.0-or-later")
            }.font(.caption2).foregroundStyle(.tertiary)
        }.padding(30).frame(maxWidth: .infinity)
    }

    private func shortcutRow(_ title: String, shortcut: Binding<Shortcut>, action: ShortcutAction) -> some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(shortcut: shortcut, title: title, monitor: model.hotkeys,
                             validate: { store.value.shortcutConflict($0, for: action) }).frame(width: 160, height: 28)
        }
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted { Label(L10n.text("已允许", "Granted"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Button(L10n.text("允许…", "Allow…"), action: action) }
        }
    }

    private func instruction(_ key: String, _ detail: String) -> some View {
        LabeledContent(detail) { Text(key).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
    }

    private func positionName(_ anchor: ZoomAnchor, language: AppLanguage) -> String {
        switch anchor {
        case .topLeft: return L10n.text("左上", "Top left", language: language)
        case .top: return L10n.text("上方", "Top", language: language)
        case .topRight: return L10n.text("右上", "Top right", language: language)
        case .left: return L10n.text("左侧", "Left", language: language)
        case .center: return L10n.text("居中", "Center", language: language)
        case .right: return L10n.text("右侧", "Right", language: language)
        case .bottomLeft: return L10n.text("左下", "Bottom left", language: language)
        case .bottom: return L10n.text("下方", "Bottom", language: language)
        case .bottomRight: return L10n.text("右下", "Bottom right", language: language)
        }
    }
}

enum SettingsPage: CaseIterable, Hashable, Identifiable {
    case general, keyboard, floatingWindows, appearance, media, detection, about
    var id: Self { self }
    func title(in language: AppLanguage) -> String {
        switch self {
        case .general: return L10n.text("通用", "General", language: language)
        case .floatingWindows: return L10n.text("浮窗", "Panels", language: language)
        case .appearance: return L10n.text("外观", "Appearance", language: language)
        case .media: return L10n.text("媒体", "Media", language: language)
        case .detection: return L10n.text("检测与自动化", "Detection & Automation", language: language)
        case .keyboard: return L10n.text("快捷键", "Shortcuts", language: language)
        case .about: return L10n.text("关于", "About", language: language)
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
    let title: String
    let monitor: HotkeyMonitor
    let validate: (Shortcut) -> String?
    func makeNSView(context: Context) -> ShortcutButton { ShortcutButton(frame: .zero) }
    func updateNSView(_ view: ShortcutButton, context: Context) {
        if !view.recording { view.title = shortcut.display }
        view.setAccessibilityLabel(title)
        view.setAccessibilityValue(shortcut.display)
        view.savedTitle = shortcut.display
        view.onRecord = { shortcut = $0 }
        view.validate = validate
        view.onRecording = { monitor.recording = $0 }
    }
    static func dismantleNSView(_ view: ShortcutButton, coordinator: ()) { view.finishRecording() }
}

struct QuickCaptureRecorder: NSViewRepresentable {
    @Binding var modifiers: QuickCaptureModifiers
    let language: AppLanguage
    let monitor: HotkeyMonitor
    func makeNSView(context: Context) -> ShortcutButton {
        let view = ShortcutButton(frame: .zero)
        view.modifierOnly = true
        return view
    }
    func updateNSView(_ view: ShortcutButton, context: Context) {
        let title = L10n.text("\(modifiers.display) + 双击", "\(modifiers.display) + double-click", language: language)
        view.isEnabled = context.environment.isEnabled
        if !view.recording { view.title = title }
        view.savedTitle = title
        view.onRecordModifiers = { modifiers = $0 }
        view.onRecording = { monitor.recording = $0 }
        view.setAccessibilityLabel(L10n.text("编辑快速捕获手势", "Edit quick capture gesture", language: language))
        view.setAccessibilityValue(title)
    }
    static func dismantleNSView(_ view: ShortcutButton, coordinator: ()) { view.finishRecording() }
}

final class ShortcutButton: NSButton {
    var onRecord: ((Shortcut) -> Void)?
    var onRecordModifiers: ((QuickCaptureModifiers) -> Void)?
    var modifierOnly = false
    var onRecording: ((Bool) -> Void)?
    var validate: ((Shortcut) -> String?)?
    var savedTitle = ""
    private(set) var recording = false
    private var eventMonitor: Any?
    private var observer: NSObjectProtocol?
    private var modifierRecording = ModifierChordRecording()
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
        modifierRecording.reset()
        title = modifierOnly ? L10n.text("按住组合后松开 · Esc 取消", "Hold, release · Esc cancels") : L10n.text("按下快捷键 · Esc 取消", "Press keys · Esc cancels")
        let mask: NSEvent.EventTypeMask = modifierOnly ? [.keyDown, .flagsChanged] : .keyDown
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.recording else { return event }
            self.capture(event)
            return nil
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishRecording() }
        }
    }

    func finishRecording() {
        modifierRecording.reset()
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
        if event.type == .keyDown && event.keyCode == 53 { finishRecording(); return }
        let flags = event.modifierFlags
        if modifierOnly {
            guard event.type == .flagsChanged else {
                modifierRecording.rejectUntilRelease()
                title = L10n.text("仅使用修饰键 · Esc 取消", "Modifiers only · Esc cancels")
                return
            }
            let held = QuickCaptureModifiers(command: flags.contains(.command), option: flags.contains(.option),
                                             control: flags.contains(.control), shift: flags.contains(.shift),
                                             function: flags.contains(.function))
            if let value = modifierRecording.update(held) {
                savedTitle = L10n.text("\(value.display) + 双击", "\(value.display) + double-click")
                onRecordModifiers?(value)
                finishRecording()
            } else if !modifierRecording.candidate.isEmpty {
                title = L10n.text("\(modifierRecording.candidate.display) + 双击 · 松开保存", "\(modifierRecording.candidate.display) · Release to save")
            }
            return
        }
        guard !flags.intersection([.command, .control, .option, .function, .shift]).isEmpty else {
            title = L10n.text("请同时按住修饰键", "Hold a modifier key"); return
        }
        let label: String
        switch event.keyCode {
        case 49: label = "Space"; case 36: label = "Return"; case 48: label = "Tab"; case 51: label = "Delete"
        default: label = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        }
        let value = Shortcut(keyCode: event.keyCode, command: flags.contains(.command), option: flags.contains(.option),
                             control: flags.contains(.control), function: flags.contains(.function), shift: flags.contains(.shift), label: label)
        if let issue = validate?(value) { title = L10n.text("快捷键冲突，请重新输入", "Conflict; try again"); toolTip = issue; NSSound.beep(); return }
        savedTitle = value.display
        onRecord?(value)
        finishRecording()
    }
}
#endif
