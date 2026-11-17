#if os(macOS)
import AppKit
import SwiftUI
import IceCore

@MainActor
final class SettingsWindowState: ObservableObject {
    @Published var selection: SettingsPage? = .general {
        didSet { if selection != .appearance { images.cancelLoading() } }
    }
    @Published var showOriginal = false
    let images = AppearanceImageStore()
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: ApplicationModel
    let state = SettingsWindowState()
    private(set) var window: NSWindow?
    private var savedFrame: NSRect?
    private let releaseDelay: Duration
    private lazy var lifetime = SettingsResourceLifetime(delay: releaseDelay) { [weak self] in
        self?.releaseResources()
    }
    private var pressureSource: DispatchSourceMemoryPressure?

    init(model: ApplicationModel, releaseDelay: Duration = .seconds(180)) {
        self.model = model
        self.releaseDelay = releaseDelay
        super.init()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let events = self.pressureSource?.data else { return }
                self.lifetime.memoryPressureChanged(isElevated: !events.intersection([.warning, .critical]).isEmpty)
            }
        }
        pressureSource = source
        source.resume()
    }

    deinit { pressureSource?.cancel() }

    func show() {
        lifetime.opened()
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if window == nil {
            let created = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 820, height: 640),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
            created.backgroundColor = .windowBackgroundColor
            created.toolbarStyle = .unified
            created.contentMinSize = NSSize(width: 740, height: 540)
            created.isReleasedWhenClosed = false
            created.delegate = self
            created.contentViewController = NSHostingController(rootView: SettingsView(model: model, store: model.settings, state: state))
            created.setFrameAutosaveName("IceScreen.Settings")
            if let savedFrame { created.setFrame(savedFrame, display: false) }
            else if !created.setFrameUsingName("IceScreen.Settings") { created.center() }
            window = created
        }
        updateTitle()
        if state.selection == .appearance { state.images.restoreIfNeeded() }
        model.checkPermissions()
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateTitle() {
        window?.title = L10n.text("IceScreen 设置", "IceScreen Settings")
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as AnyObject? === window else { return }
        savedFrame = window?.frame
        state.images.cancelLoading()
        model.hotkeys.recording = false
        lifetime.closed()
        NSApp.setActivationPolicy(.accessory)
    }

    private func releaseResources() {
        guard let window, !window.isVisible else { return }
        window.delegate = nil
        window.contentViewController = nil
        window.contentView = nil
        self.window = nil
        state.images.releaseDecodedImage()
        AppearanceSample.clearCache()
    }
}
#endif
