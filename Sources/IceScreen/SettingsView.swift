#if os(macOS)
import AppKit
import SwiftUI
import IceCore

struct SettingsView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var store: SettingsStore
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $page) {
                Label("通用", systemImage: "gearshape").tag(0)
                Label("浮窗", systemImage: "pip").tag(1)
                Label("捕获", systemImage: "rectangle.dashed").tag(2)
                Label("操作", systemImage: "keyboard").tag(3)
                Label("关于", systemImage: "info.circle").tag(4)
            }
            .pickerStyle(.segmented).labelsHidden().padding(8).modifier(IceGlass())
            .padding(.horizontal, 24).padding(.vertical, 12)
            Group {
                switch page {
                case 1: floatingWindows
                case 2: capture
                case 3: keyboard
                case 4: about
                default: general
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 8)
        .frame(width: 620, height: 610)
        .alert("IceScreen", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("好", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var general: some View {
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
                Button("恢复默认快捷键") {
                    store.value.shortcut = Shortcut()
                    store.value.regionShortcut = nil
                    store.value.closeAllShortcut = nil
                }.controlSize(.small)
            } header: { Text("快捷键") } footer: {
                Text("支持 ⌘、⌥、⌃、⇧ 和 fn 组合。例如 ⌘⇧I；其自动区域快捷键为 ⌥⇧⌘I。")
            }
            Section {
                Picker("触发修饰键", selection: $store.value.triggerModifier) {
                    ForEach(TriggerModifier.allCases, id: \.self) { Text($0.display).tag($0) }
                }
            } footer: {
                Text("轻按隐藏或恢复浮窗，双击切换自动隐藏；按住并双击来源窗口可快速捕获区域。")
            }
            Section("启动") {
                Toggle("登录时启动 IceScreen", isOn: Binding(get: { model.loginEnabled }, set: model.setLaunchAtLogin))
            }
            Section("系统权限") {
                permissionRow("屏幕录制", granted: model.screenPermission, action: model.requestScreenPermission)
                permissionRow("辅助功能", granted: model.accessibilityPermission, action: model.requestAccessibility)
                if !model.hotkeysActive && model.accessibilityPermission {
                    Label("全局按键尚未启用，请检查系统的输入监控权限。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("重新检查权限") { model.checkPermissions() }
            }
        }.formStyle(.grouped)
    }

    private var floatingWindows: some View {
        Form {
            Section("窗口行为") {
                Toggle("多窗口模式", isOn: $store.value.multiWindow)
                Picker("出现位置", selection: $store.value.panelPosition) {
                    ForEach(ZoomAnchor.allCases, id: \.self) { Text(positionName($0)).tag($0) }
                }
                Toggle("显示在全屏桌面空间", isOn: $store.value.showOnFullscreenSpaces)
                Toggle("单击定位来源窗口", isOn: $store.value.clickToFocus)
                Picker("来源窗口获得焦点时", selection: $store.value.sourceFocusBehavior) {
                    Text("保持浮窗").tag(SourceFocusBehavior.keep)
                    Text("暂停捕获").tag(SourceFocusBehavior.pause)
                    Text("关闭浮窗").tag(SourceFocusBehavior.close)
                }
            }
            Section {
                Toggle("鼠标移入时自动隐藏", isOn: $store.value.autoHide)
            } footer: {
                Text("悬停时双击 \(store.value.triggerModifier.display) 可随时开关自动隐藏。浮窗透明时仍可按 Delete 关闭，或双击 \(store.value.triggerModifier.display) 恢复显示和操作。")
            }
            Section("浮窗显示") {
                Toggle("显示操作提示", isOn: $store.value.showHoverHints)
                Toggle("Space 预览来源窗口", isOn: $store.value.quickLook)
                LabeledContent("圆角", value: "\(Int(store.value.cornerRadius)) pt")
                Slider(value: $store.value.cornerRadius, in: 0...30, step: 1)
            }
            Section("关闭所有浮窗") {
                Toggle("启用快捷键", isOn: Binding(get: { store.value.closeAllShortcut != nil }, set: {
                    let candidate = Shortcut(keyCode: 35, command: true, function: false, shift: true, label: "P")
                    if $0, let issue = store.value.shortcutConflict(candidate, for: .closeAll) { model.error = issue }
                    else { store.value.closeAllShortcut = $0 ? candidate : nil }
                }))
                if store.value.closeAllShortcut != nil {
                    shortcutRow("全部关闭", shortcut: Binding(get: { store.value.closeAllShortcut! }, set: { store.value.closeAllShortcut = $0 }), action: .closeAll)
                }
            }
        }.formStyle(.grouped)
    }

    private var capture: some View {
        Form {
            Section {
                Picker("默认帧率", selection: $store.value.defaultFPS) {
                    ForEach(Preferences.frameRates, id: \.self) { Text("\($0) FPS").tag($0) }
                }
                Toggle("增强对比度和清晰度", isOn: $store.value.enhanceContrast)
                Toggle("\(store.value.triggerModifier.display) + 双击快速捕获局部区域", isOn: $store.value.quickRegionCapture)
            } header: { Text("画面") } footer: {
                Text("默认 10 FPS。静态进度可用 1 FPS，视频可用 30 或 60 FPS。悬停时按 F 打开帧率菜单，选择会按应用保存。")
            }
            Section {
                Toggle("检测内容空闲", isOn: $store.value.idleDetection)
                Picker("无变化多久后提示", selection: $store.value.idleSeconds) {
                    ForEach([5.0, 10, 20, 30, 60, 120], id: \.self) { Text("\(Int($0)) 秒").tag($0) }
                }
            } header: { Text("内容检测") } footer: {
                Text("悬停时按 D，或点击右上角状态点，可以为单个浮窗开关检测。")
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
        }.formStyle(.grouped)
    }

    private var keyboard: some View {
        Form {
            Section("捕获") {
                instruction(store.value.shortcut.display, "捕获当前窗口")
                instruction(store.value.effectiveRegionShortcut?.display ?? "未设置", "选择捕获区域")
                instruction("\(store.value.triggerModifier.display) + 双击来源窗口", "捕获鼠标附近区域")
            }
            Section("鼠标位于浮窗上时") {
                instruction("轻按 \(store.value.triggerModifier.display)", "隐藏 / 恢复浮窗")
                instruction("双击 \(store.value.triggerModifier.display)", "切换自动隐藏")
                instruction("Space", "预览来源窗口；长按松开关闭")
                instruction("Delete", "关闭浮窗（透明时也有效）")
                instruction("F", "打开应用帧率菜单")
                instruction("D", "切换内容空闲检测")
                instruction("双击", "定位来源窗口并关闭浮窗")
                instruction("⌘ + 拖动", "框选缩放区域")
                instruction("⌘ + 双击", "恢复完整画面")
                instruction("滚动 / ⌘ + 滚动", "平移 / 缩放")
                instruction("捏合 / = / −", "缩放画面")
            }
            Section {
                Text("手动隐藏后，浮窗会等待 60 秒，再自动关闭。自动隐藏会在鼠标离开时恢复。")
                Text("系统设置 → 键盘可将 fn / 地球键设为「不执行操作」，避免同时触发系统功能。")
            }.font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "pip").font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint).padding(28).modifier(IceGlass())
            VStack(spacing: 6) {
                Text("IceScreen").font(.largeTitle.weight(.semibold))
                Text("1.1.0").foregroundStyle(.secondary)
            }
            Text("让你关注的窗口，留在眼前。")
            Text("原生窗口捕获 · 本机处理 · GPL-3.0-or-later")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("Copyright © 2026 IceScreen contributors").font(.caption2).foregroundStyle(.tertiary)
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

struct IceGlass: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
        #else
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        #endif
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
