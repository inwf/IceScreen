#if os(macOS)
import AppKit
import SwiftUI
import CoreVideo
import IceCore

struct AppearanceSettings: View {
    @ObservedObject var store: SettingsStore
    @State private var showHover = false
    @State private var showOriginal = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("即时预览").font(.headline)
                    Spacer()
                    Toggle("悬停效果", isOn: $showHover).toggleStyle(.button)
                    Toggle("对比原图", isOn: $showOriginal).toggleStyle(.button)
                        .help("临时查看未增强的示例画面，不改变浮窗设置")
                }
                .controlSize(.small)
                AppearancePreview(preferences: store.value, hovered: showHover, original: showOriginal)
                    .frame(height: 204)
                    .accessibilityLabel("浮窗外观示例")
                    .accessibilityValue("圆角 \(Int(store.value.cornerRadius)) 点，透明度 \(Int(store.value.panelOpacity * 100))%，\(showOriginal || !store.value.enhanceContrast ? "原始画面" : "已增强对比度和锐度")")
                Text(showOriginal ? "正在对比原始画面 · 圆角和透明度仍按当前设置显示" : "内置文字与图形示例 · 调整会同时应用到当前浮窗")
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
                    Toggle("悬停时控件周围变暗", isOn: $store.value.dimOnHover)
                    LabeledContent("边缘效果强度", value: "\(Int(store.value.hoverBlur * 100))%")
                    Slider(value: $store.value.hoverBlur, in: 0...1, step: 0.05) { Text("边缘效果强度") }
                        .disabled(!store.value.dimOnHover)
                    Toggle("显示操作提示", isOn: $store.value.showHoverHints)
                } header: { Text("悬停外观") } footer: {
                    Text("打开预览上方的「悬停效果」查看按钮、边缘材质和操作提示。")
                }
            }.formStyle(.grouped)
        }
    }
}

struct AppearancePreview: NSViewRepresentable {
    let preferences: Preferences
    let hovered: Bool
    let original: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> AppearancePreviewView { AppearancePreviewView(frame: .zero) }
    func updateNSView(_ view: AppearancePreviewView, context: Context) {
        view.update(preferences, hovered: hovered, original: original, dark: colorScheme == .dark)
    }
    static func dismantleNSView(_ view: AppearancePreviewView, coordinator: ()) { view.releasePreview() }
}

@MainActor
final class AppearancePreviewView: NSView {
    let surface = PanelSurface(frame: .zero)
    private var sample: CVPixelBuffer?
    private var dark = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        addSubview(surface)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(_ preferences: Preferences, hovered: Bool, original: Bool, dark: Bool) {
        if sample == nil || self.dark != dark {
            self.dark = dark
            sample = dark ? AppearanceSample.dark : AppearanceSample.light
            needsDisplay = true
            if let sample { surface.frameView.display(sample) }
        }
        surface.applyAppearance(preferences, enhanced: preferences.enhanceContrast && !original)
        surface.alphaValue = preferences.panelOpacity
        if surface.clickToFocus != preferences.clickToFocus { surface.clickToFocus = preferences.clickToFocus }
        if surface.triggerLabel != preferences.triggerModifier.display { surface.triggerLabel = preferences.triggerModifier.display }
        surface.setHovered(hovered)
    }

    override func layout() {
        super.layout()
        let width = max(0, min(320, bounds.width - 48, (bounds.height - 24) * 16 / 9))
        surface.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - width * 9 / 16) / 2,
                               width: width, height: width * 9 / 16)
        surface.layoutSubtreeIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let sample { surface.frameView.display(sample) }
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

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func releasePreview() {
        surface.setHovered(false)
        surface.frameView.releaseFrame()
        sample = nil
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
