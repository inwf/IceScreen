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
    private let defaults = Preferences()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.text("即时预览", "Live preview")).font(.headline)
                    Spacer()
                    if images.isLoading { ProgressView().controlSize(.small) }
                    Button(L10n.text("选择图片…", "Choose image…")) { showImagePicker = true }
                    if images.image != nil {
                        Button(L10n.text("恢复示例", "Reset sample")) { images.reset() }
                    }
                    Toggle(L10n.text("对比原图", "Compare original"), isOn: $showOriginal).toggleStyle(.button)
                        .help(L10n.text("临时查看未增强的示例画面，不改变浮窗设置", "Preview the original image without changing panel settings"))
                }
                .controlSize(.small)
                AppearancePreview(preferences: store.value, original: showOriginal, image: images.image)
                    .frame(height: 204)
                    .accessibilityLabel(L10n.text("浮窗外观示例", "Panel appearance preview"))
                    .accessibilityValue(L10n.text("圆角 \(Int(store.value.cornerRadius)) 点，透明度 \(Int(store.value.panelOpacity * 100))%，\(showOriginal || !store.value.enhanceContrast ? "原始画面" : "已增强对比度和锐度")", "Corner radius \(Int(store.value.cornerRadius)) points, opacity \(Int(store.value.panelOpacity * 100))%, \(showOriginal || !store.value.enhanceContrast ? "original image" : "enhanced contrast and sharpness")"))
                Text(showOriginal ? L10n.text("正在对比原始画面 · 圆角和透明度仍按当前设置显示", "Comparing original · current corner radius and opacity still apply") : (images.image?.name ?? L10n.text("内置文字与图形示例", "Built-in text and graphics sample")))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text(store.value.autoHide ? L10n.text("鼠标移入后按隐藏时透明度显示，移出后恢复。", "Hover to preview auto-hide opacity; move away to restore.") : L10n.text("鼠标移入画面预览按钮、边缘阴影和操作提示。", "Hover to preview controls, edge shading, and hints."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)
            Divider()
            Form {
                Section(L10n.text("形状与透明度", "Shape and opacity")) {
                    DefaultValueSlider(id: "cornerRadius", title: L10n.text("圆角", "Corner radius"), value: $store.value.cornerRadius,
                                       range: 0...30, step: 1, defaultValue: defaults.cornerRadius,
                                       format: { "\(Int($0.rounded())) pt" })
                    DefaultValueSlider(id: "panelOpacity", title: L10n.text("透明度", "Opacity"), value: $store.value.panelOpacity,
                                       range: 0.35...1, step: 0.01, defaultValue: defaults.panelOpacity,
                                       format: { "\(Int(($0 * 100).rounded()))%" })
                }
                Section {
                    Toggle(L10n.text("增强对比度和锐度", "Enhance contrast and sharpness"), isOn: $store.value.enhanceContrast)
                    DefaultValueSlider(id: "contrastStrength", title: L10n.text("对比度强度", "Contrast"), value: $store.value.contrastStrength,
                                       range: 0...1, step: 0.01, defaultValue: defaults.contrastStrength,
                                       format: { "\(Int(($0 * 100).rounded()))%" })
                        .disabled(!store.value.enhanceContrast)
                    DefaultValueSlider(id: "sharpnessStrength", title: L10n.text("锐化强度", "Sharpness"), value: $store.value.sharpnessStrength,
                                       range: 0...1, step: 0.01, defaultValue: defaults.sharpnessStrength,
                                       format: { "\(Int(($0 * 100).rounded()))%" })
                        .disabled(!store.value.enhanceContrast)
                } header: { Text(L10n.text("画面清晰度", "Image clarity")) } footer: {
                    Text(L10n.text("两项强度均可按 1% 调整。0% 保留原始效果，使用「对比原图」查看增强前后的差异。", "Adjust each strength in 1% steps. At 0%, the original image is preserved. Use Compare original to see the difference."))
                }
                Section {
                    Toggle(L10n.text("鼠标移入时自动隐藏", "Auto-hide on hover"), isOn: $store.value.autoHide)
                    DefaultValueSlider(id: "autoHideOpacity", title: L10n.text("隐藏时透明度", "Hidden opacity"), value: $store.value.autoHideOpacity,
                                       range: 0...1, step: 0.01, defaultValue: defaults.autoHideOpacity,
                                       format: { "\(Int(($0 * 100).rounded()))%" })
                } header: { Text(L10n.text("自动隐藏", "Auto-hide")) } footer: {
                    Text(L10n.text("0% 完全透明，100% 完全不透明。鼠标移入后保持穿透，移出后恢复正常透明度。双击 \(store.value.triggerModifier.display) 开启自动隐藏的浮窗也使用此设置。", "0% is fully transparent; 100% is fully opaque. The pointer passes through while hovering. Move away to restore normal opacity. This also applies when auto-hide is enabled by double-tapping \(store.value.triggerModifier.display)."))
                }
                Section {
                    Toggle(L10n.text("悬停时控件周围变暗", "Dim around controls on hover"), isOn: $store.value.dimOnHover)
                    DefaultValueSlider(id: "hoverBlur", title: L10n.text("边缘效果强度", "Edge shading"), value: $store.value.hoverBlur,
                                       range: 0...1, step: 0.01, defaultValue: defaults.hoverBlur,
                                       format: { "\(Int(($0 * 100).rounded()))%" })
                        .disabled(!store.value.dimOnHover)
                    Toggle(L10n.text("显示操作提示", "Show control hints"), isOn: $store.value.showHoverHints)
                        .help(L10n.text("鼠标移入时在左下角显示常用操作，并跟随单击定位、Space 预览和缩放状态更新。", "Show common actions in the lower left on hover. Hints follow click-to-focus, Space preview, and zoom settings."))
                } header: { Text(L10n.text("悬停外观", "Hover appearance")) } footer: {
                    Text(L10n.text("预览跟随鼠标自动展示当前设置。实际浮窗隐藏后，可双击 \(store.value.triggerModifier.display) 恢复显示和操作，或按 Delete 关闭。", "Hover to preview your settings. When a panel is hidden, double-tap \(store.value.triggerModifier.display) to restore it and its controls, or press Delete to close it."))
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
        .alert(L10n.text("无法读取图片", "Unable to read image"), isPresented: Binding(get: { images.error != nil }, set: { if !$0 { images.error = nil } })) {
            Button(L10n.text("好", "OK"), role: .cancel) { images.error = nil }
        } message: { Text(images.error ?? "") }
        .onDisappear { images.cancelLoading() }
    }
}

struct DefaultValueSlider: View {
    let id: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let format: (Double) -> String

    private var sliderValue: Binding<Double> {
        Binding(get: { value }, set: { proposed in
            let rounded = range.lowerBound + ((proposed - range.lowerBound) / step).rounded() * step
            value = min(range.upperBound, max(range.lowerBound, rounded))
        })
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).frame(width: L10n.language == .english ? 112 : 84, height: 22, alignment: .leading)
            VStack(spacing: 0) {
                Slider(value: sliderValue, in: range) { Text(title) }
                    .labelsHidden()
                    .frame(height: 22)
                    .accessibilityValue(format(value))
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: sliderValue.wrappedValue = value + step
                        case .decrement: sliderValue.wrappedValue = value - step
                        @unknown default: break
                        }
                    }
                GeometryReader { geometry in
                    let fraction = (defaultValue - range.lowerBound) / (range.upperBound - range.lowerBound)
                    let center = 10 + (geometry.size.width - 20) * fraction
                    let labelWidth = min(88, geometry.size.width)
                    let origin = min(max(0, center - labelWidth / 2), geometry.size.width - labelWidth)
                    Button { value = defaultValue } label: {
                        VStack(spacing: 3) {
                            Circle().fill(.secondary).frame(width: 5, height: 5)
                                .offset(x: center - origin - labelWidth / 2)
                            Text(L10n.text("默认 \(format(defaultValue))", "Default \(format(defaultValue))"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: labelWidth, height: 28, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: origin)
                    .help(L10n.text("恢复\(title)默认值：\(format(defaultValue))", "Reset \(title) to \(format(defaultValue))"))
                    .accessibilityLabel(L10n.text("恢复\(title)默认值", "Reset \(title) to default"))
                    .accessibilityValue(format(defaultValue))
                    .accessibilityIdentifier("appearance.default.\(id)")
                }.frame(height: 28)
            }.frame(minWidth: 140)
            Text(format(value)).monospacedDigit()
                .frame(width: 50, height: 22, alignment: .trailing)
        }
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
        let appearanceChanged = self.dark != dark || self.preferences.language != preferences.language
        self.dark = dark
        self.preferences = preferences
        if appearanceChanged { needsDisplay = true }
        if sample == nil || imageID != image?.id || (image == nil && appearanceChanged) {
            surface.frameView.releaseFrame()
            imageID = image?.id
            sample = image?.pixels ?? AppearanceSample.image(dark: dark, language: preferences.language)
            surface.frameView.layer?.isOpaque = image == nil
            if let sample { surface.frameView.display(sample) }
            needsLayout = true
        }
        surface.applyAppearance(preferences, enhanced: preferences.enhanceContrast && !original)
        if surface.clickToFocus != preferences.clickToFocus { surface.clickToFocus = preferences.clickToFocus }
        if surface.previewEnabled != preferences.quickLook { surface.previewEnabled = preferences.quickLook }
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
        let opacity = pointerInside && preferences.autoHide ? preferences.autoHideOpacity : preferences.panelOpacity
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
    static var light: CVPixelBuffer { image(dark: false, language: L10n.language) }
    static var dark: CVPixelBuffer { image(dark: true, language: L10n.language) }
    private static var samples: [AppLanguage: [Bool: CVPixelBuffer]] = [:]

    static func image(dark: Bool, language: AppLanguage) -> CVPixelBuffer {
        if let sample = samples[language]?[dark] { return sample }
        let sample = make(dark: dark, language: language)
        samples[language, default: [:]][dark] = sample
        return sample
    }

    private static func make(dark: Bool, language: AppLanguage) -> CVPixelBuffer {
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
        text(L10n.text("细节清晰，专注眼前", "Clear details. Stay focused.", language: language), x: 20, y: 114, size: 12, color: secondary)
        text("Aa  0123456789", x: 20, y: 84, size: 15, color: ink)
        text(L10n.text("文字与细线 · 对比锐化效果", "Text and lines · Compare clarity", language: language), x: 20, y: 64, size: 10, color: secondary)
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
