#if os(macOS)
import AppKit
import SwiftUI
import CoreVideo
import IceCore
import UniformTypeIdentifiers

struct AppearanceSettings: View {
    @ObservedObject var store: SettingsStore
    @State private var showOriginal = false
    @State private var showImagePicker = false
    @StateObject private var images = AppearanceImageStore()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("即时预览").font(.headline)
                    Spacer()
                    if images.isLoading { ProgressView().controlSize(.small) }
                    Button("选择图片…") { showImagePicker = true }
                    if images.image != nil {
                        Button("恢复示例") { images.reset() }
                    }
                    Toggle("对比原图", isOn: $showOriginal).toggleStyle(.button)
                        .help("临时查看未增强的示例画面，不改变浮窗设置")
                }
                .controlSize(.small)
                AppearancePreview(preferences: store.value, original: showOriginal, image: images.image)
                    .frame(height: 204)
                    .accessibilityLabel("浮窗外观示例")
                    .accessibilityValue("圆角 \(Int(store.value.cornerRadius)) 点，透明度 \(Int(store.value.panelOpacity * 100))%，\(showOriginal || !store.value.enhanceContrast ? "原始画面" : "已增强对比度和锐度")")
                Text(showOriginal ? "正在对比原始画面 · 圆角和透明度仍按当前设置显示" : (images.image?.name ?? "内置文字与图形示例"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(store.value.autoHide ? "鼠标移入画面预览自动隐藏，移出后恢复。" : "鼠标移入画面预览按钮、边缘阴影和操作提示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
            Divider()
            Form {
                Section("形状与透明度") {
                    LabeledContent("圆角", value: "\(Int(store.value.cornerRadius)) pt")
                    Slider(value: $store.value.cornerRadius, in: 0...30, step: 1) { Text("圆角") }
                    LabeledContent("透明度", value: "\(Int(store.value.panelOpacity * 100))%")
                    Slider(value: $store.value.panelOpacity, in: 0.35...1, step: 0.05) { Text("透明度") }
                }
                Section {
                    Toggle("增强对比度和锐度", isOn: $store.value.enhanceContrast)
                } header: { Text("画面清晰度") } footer: {
                    Text("观察预览中的小字、细线和渐变，使用「对比原图」查看增强前后的差异。")
                }
                Section {
                    Toggle("鼠标移入时自动隐藏", isOn: $store.value.autoHide)
                    Toggle("悬停时控件周围变暗", isOn: $store.value.dimOnHover)
                    LabeledContent("边缘效果强度", value: "\(Int(store.value.hoverBlur * 100))%")
                    Slider(value: $store.value.hoverBlur, in: 0...1, step: 0.05) { Text("边缘效果强度") }
                        .disabled(!store.value.dimOnHover)
                    Toggle("显示操作提示", isOn: $store.value.showHoverHints)
                } header: { Text("悬停外观") } footer: {
                    Text("预览跟随鼠标自动展示当前设置。实际浮窗隐藏后，可双击 \(store.value.triggerModifier.display) 恢复显示和操作，或按 Delete 关闭。")
                }
            }.formStyle(.grouped)
        }
        .fileImporter(isPresented: $showImagePicker, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): images.load(url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { images.error = error.localizedDescription }
            }
        }
        .alert("无法读取图片", isPresented: Binding(get: { images.error != nil }, set: { if !$0 { images.error = nil } })) {
            Button("好", role: .cancel) { images.error = nil }
        } message: { Text(images.error ?? "") }
        .onDisappear { images.cancelLoading() }
    }
}

struct AppearancePreview: NSViewRepresentable {
    let preferences: Preferences
    let original: Bool
    let image: AppearanceImage?
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> AppearancePreviewView { AppearancePreviewView(frame: .zero) }
    func updateNSView(_ view: AppearancePreviewView, context: Context) {
        view.update(preferences, original: original, dark: colorScheme == .dark, image: image)
    }
    static func dismantleNSView(_ view: AppearancePreviewView, coordinator: ()) { view.releasePreview() }
}

@MainActor
final class AppearancePreviewView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    let surface = PanelSurface(frame: .zero)
    private var sample: CVPixelBuffer?
    private var dark = false
    private var imageID: UUID?
    private var preferences = Preferences()
    private var tracking: NSTrackingArea?
    private(set) var pointerInside = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(surface)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(_ preferences: Preferences, original: Bool, dark: Bool, image: AppearanceImage? = nil) {
        let appearanceChanged = self.dark != dark
        self.dark = dark
        self.preferences = preferences
        if appearanceChanged { needsDisplay = true }
        if sample == nil || imageID != image?.id || (image == nil && appearanceChanged) {
            imageID = image?.id
            sample = image?.pixels ?? (dark ? AppearanceSample.dark : AppearanceSample.light)
            surface.frameView.layer?.isOpaque = image == nil
            if let sample { surface.frameView.display(sample) }
            needsLayout = true
        }
        surface.applyAppearance(preferences, enhanced: preferences.enhanceContrast && !original)
        if surface.clickToFocus != preferences.clickToFocus { surface.clickToFocus = preferences.clickToFocus }
        if surface.triggerLabel != preferences.triggerModifier.display { surface.triggerLabel = preferences.triggerModifier.display }
        applyHover(animated: false)
    }

    override func layout() {
        super.layout()
        let ratio = sample.map { CGFloat(CVPixelBufferGetWidth($0)) / CGFloat(CVPixelBufferGetHeight($0)) } ?? 16 / 9
        let width = max(0, min(320, bounds.width - 48, (bounds.height - 24) * ratio))
        surface.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - width / ratio) / 2,
                               width: width, height: width / ratio)
        surface.layoutSubtreeIfNeeded()
        updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let sample { surface.frameView.display(sample) }
        if window == nil { setPointerInside(false) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if window != nil, tracking?.rect == surface.frame { return }
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        guard let window, !surface.frame.isEmpty else { setPointerInside(false); return }
        let area = NSTrackingArea(rect: surface.frame, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area)
        tracking = area
        setPointerInside(surface.frame.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
    }

    override func mouseEntered(with event: NSEvent) { setPointerInside(true) }
    override func mouseExited(with event: NSEvent) { setPointerInside(false) }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    private func setPointerInside(_ value: Bool) {
        guard pointerInside != value else { return }
        pointerInside = value
        applyHover(animated: true)
    }

    private func applyHover(animated: Bool) {
        surface.setHovered(pointerInside)
        let opacity = pointerInside && preferences.autoHide ? 0 : preferences.panelOpacity
        guard surface.alphaValue != opacity else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0
            surface.animator().alphaValue = opacity
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let base = dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.88, alpha: 1)
        base.setFill()
        bounds.fill()
        let tile = dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.white.withAlphaComponent(0.45)
        tile.setFill()
        let side: CGFloat = 16
        for row in 0..<Int(ceil(bounds.height / side)) {
            for column in 0..<Int(ceil(bounds.width / side)) where (row + column).isMultiple(of: 2) {
                NSRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side).fill()
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, bounds.contains(local) else { return nil }
        let windowPoint = convert(local, to: nil)
        if surface.alphaValue > 0, let action = surface.control(atWindowPoint: windowPoint), action != .resize {
            return surface.target(atWindowPoint: windowPoint)
        }
        return self
    }

    func releasePreview() {
        surface.setHovered(false)
        surface.frameView.releaseFrame()
        sample = nil
        imageID = nil
        pointerInside = false
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
    }
}

@MainActor
enum AppearanceSample {
    static let light = make(dark: false)
    static let dark = make(dark: true)

    private static func make(dark: Bool) -> CVPixelBuffer {
        let width = 640, height = 360
        var result: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferCGImageCompatibilityKey: true,
                                         kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &result)
        guard status == kCVReturnSuccess, let result else { fatalError("Cannot allocate appearance sample: \(status)") }
        let locked = CVPixelBufferLockBaseAddress(result, [])
        precondition(locked == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(result), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(result),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            fatalError("Cannot create appearance sample drawing context.")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.scaleBy(x: 2, y: 2)
        let background = NSColor(calibratedWhite: dark ? 0.19 : 0.96, alpha: 1)
        background.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 180).fill()
        let ink = NSColor(calibratedWhite: dark ? 0.82 : 0.25, alpha: 1)
        let secondary = NSColor(calibratedWhite: dark ? 0.57 : 0.55, alpha: 1)
        func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
            (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
            ])
        }
        text("IceScreen", x: 20, y: 136, size: 17, color: ink, weight: .semibold)
        text("细节清晰，专注眼前", x: 20, y: 114, size: 12, color: secondary)
        text("Aa  0123456789", x: 20, y: 84, size: 15, color: ink)
        text("文字与细线 · 对比锐化效果", x: 20, y: 64, size: 10, color: secondary)
        let colors = [NSColor.systemTeal, NSColor.systemBlue, NSColor.systemPurple]
        NSGradient(colors: colors)!.draw(in: NSBezierPath(roundedRect: NSRect(x: 224, y: 64, width: 76, height: 84),
                                                        xRadius: 12, yRadius: 12), angle: 35)
        context.setStrokeColor(secondary.withAlphaComponent(0.5).cgColor)
        for index in 0..<5 {
            let y = CGFloat(26 + index * 5)
            context.setLineWidth(CGFloat(index + 1) * 0.25)
            context.move(to: CGPoint(x: 20, y: y))
            context.addLine(to: CGPoint(x: 300, y: y))
            context.strokePath()
        }
        return result
    }
}
#endif
