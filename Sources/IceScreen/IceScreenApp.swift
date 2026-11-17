import Foundation
import IceCore

#if os(macOS)
import AppKit
import SwiftUI
import Combine

@main
enum IceScreenApp {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 2, arguments[0] == "--watch-source-windows" {
            SourceWindowRecovery.watch(arguments[1]); return
        }
        if arguments.count == 2, arguments[0] == "--run-detection-command" { DetectionCommand.execute(arguments[1]) }
        if arguments == ["--help"] || arguments == ["-h"] { print(CaptureRequest.usage); return }
        let request: CaptureRequest?
        do { request = arguments.isEmpty ? nil : try CaptureRequest.parse(arguments) }
        catch { fputs("IceScreen: \(error.localizedDescription)\n", stderr); exit(64) }
        let app = NSApplication.shared
        if forwardToExistingInstance(request) { return }
        let delegate = AppDelegate(initialRequest: request)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor
    private static func forwardToExistingInstance(_ request: CaptureRequest?) -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "org.icescreen.app"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else { return false }
        let center = DistributedNotificationCenter.default()
        let token = UUID().uuidString
        var acknowledged = false
        let observer = center.addObserver(forName: .init("org.icescreen.ack"), object: token, queue: .main) { _ in acknowledged = true }
        defer { center.removeObserver(observer) }
        var info: [String: Any] = ["token": token]
        if let request {
            do { info["request"] = String(decoding: try JSONEncoder().encode(request), as: UTF8.self) }
            catch { fatalError("Cannot encode capture request: \(error)") }
        }
        center.postNotificationName(.init("org.icescreen.command"), object: bundleID, userInfo: info, deliverImmediately: true)
        let deadline = Date().addingTimeInterval(3)
        while !acknowledged && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if !acknowledged { fputs("IceScreen: running instance did not acknowledge the request.\n", stderr); exit(69) }
        return true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let initialRequest: CaptureRequest?
    private var model: ApplicationModel!
    private var settingsController: SettingsWindowController!
    private var statusItem: NSStatusItem?
    private var errorSubscription: AnyCancellable?
    private var menuVisibilitySubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?

    init(initialRequest: CaptureRequest?) { self.initialRequest = initialRequest; super.init() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationIdentity.prepare()
        SourceWindowRecovery.recoverAbandoned()
        model = ApplicationModel()
        settingsController = SettingsWindowController(model: model)
        errorSubscription = model.$error.compactMap { $0 }.sink { [weak self] _ in
            DispatchQueue.main.async { self?.showSettings() }
        }
        languageSubscription = model.settings.$value.map(\.language).removeDuplicates().sink { [weak self] language in
            L10n.language = language
            self?.installMenu()
            self?.settingsController.updateTitle()
        }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = MenuBarIcon.make()
        status.button?.toolTip = "IceScreen"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        statusItem = status
        menuVisibilitySubscription = model.settings.$value.map(\.showMenuBarIcon).removeDuplicates().sink { [weak self] visible in
            self?.statusItem?.isVisible = visible
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(receive(_:)),
            name: .init("org.icescreen.command"), object: Bundle.main.bundleIdentifier ?? "org.icescreen.app")
        if let initialRequest { model.receive(initialRequest) }
        else if !model.screenPermission || !model.accessibilityPermission { showSettings() }
    }

    @objc private func receive(_ notification: Notification) {
        if let json = notification.userInfo?["request"] as? String {
            do { model.receive(try JSONDecoder().decode(CaptureRequest.self, from: Data(json.utf8))) }
            catch { model.error = error.localizedDescription; showSettings() }
        } else { showSettings() }
        if let token = notification.userInfo?["token"] as? String {
            DistributedNotificationCenter.default().postNotificationName(.init("org.icescreen.ack"), object: token,
                                                                         userInfo: nil, deliverImmediately: true)
        }
    }

    @objc func showSettings() {
        settingsController.show()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let capture = NSMenuItem(title: L10n.text("捕获当前窗口", "Capture current window") + "  \(model.settings.value.shortcut.display)", action: #selector(captureCurrent), keyEquivalent: "")
        capture.target = self; menu.addItem(capture)
        let region = NSMenuItem(title: L10n.text("捕获区域", "Capture region") + "  \(model.settings.value.effectiveRegionShortcut?.display ?? "")", action: #selector(captureRegion), keyEquivalent: "")
        region.target = self; menu.addItem(region)
        if !model.sessions.isEmpty {
            menu.addItem(.separator())
            for session in model.sessions {
                let item = NSMenuItem(title: session.appName + " — " + session.title, action: nil, keyEquivalent: "")
                item.submenu = session.makeMenu()
                menu.addItem(item)
            }
            let close = NSMenuItem(title: L10n.text("关闭全部浮窗", "Close all panels"), action: #selector(closeAll), keyEquivalent: "")
            close.target = self; menu.addItem(close)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: L10n.text("设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(withTitle: L10n.text("退出 IceScreen", "Quit IceScreen"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func captureCurrent() { model.captureFocused(region: false) }
    @objc private func captureRegion() { model.captureFocused(region: true) }
    @objc private func closeAll() { model.closeAll() }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.text("关于 IceScreen", "About IceScreen"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let settings = NSMenuItem(title: L10n.text("偏好设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("退出 IceScreen", "Quit IceScreen"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L10n.text("编辑", "Edit"))
        for (title, action, key) in [(L10n.text("撤销", "Undo"), "undo:", "z"), (L10n.text("剪切", "Cut"), "cut:", "x"), (L10n.text("复制", "Copy"), "copy:", "c"),
                                      (L10n.text("粘贴", "Paste"), "paste:", "v"), (L10n.text("全选", "Select All"), "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editItem.submenu = edit; menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.text("窗口", "Window"))
        windowMenu.addItem(withTitle: L10n.text("关闭窗口", "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: L10n.text("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu; menu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
#else
@main
enum IceScreenApp {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 2, arguments[0] == "--run-detection-command" { DetectionCommand.execute(arguments[1]) }
        if CommandLine.arguments.dropFirst().contains("--help") { print(CaptureRequest.usage); return }
        fputs("IceScreen requires macOS 14 or later. IceCore tests can run on this platform.\n", stderr)
        exit(1)
    }
}
#endif
