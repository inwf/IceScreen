#if os(macOS)
import AppKit
import SwiftUI

struct PanelMessage: View {
    enum Style { case hint, status }
    let message: String
    let style: Style
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(message: String, style: Style) {
        self.message = message
        self.style = style
    }

    static func size(for message: String, width: CGFloat, style: Style) -> CGSize {
        let font = NSFont.systemFont(ofSize: style == .hint ? 13 : 12, weight: .medium)
        let textWidth = max(1, width - 24)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let rect = (message as NSString).boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph])
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return CGSize(width: min(width, ceil(rect.width) + 24),
                      height: min(ceil(rect.height), lineHeight * (style == .hint ? 3 : 6)) + (style == .hint ? 16 : 8))
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                let shape = RoundedRectangle(cornerRadius: style == .hint ? 16 : 8)
                if reduceTransparency || contrast == .increased {
                    label.foregroundStyle(.primary)
                        .background(Color(nsColor: .windowBackgroundColor), in: shape)
                } else {
                    label.foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.85), radius: 1, y: 0.5)
                        .glassEffect(.clear, in: shape)
                }
            } else if style == .status {
                label.foregroundStyle(.white)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            } else {
                label.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .help(message)
    }

    private var label: some View {
        GeometryReader { geometry in
            let verticalPadding = min(style == .hint ? 8.0 : 4.0, max(0, (geometry.size.height - 16) / 2))
            Text(message)
                .font(.system(size: style == .hint ? 13 : 12, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(style == .hint ? 3 : 6)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, min(12, geometry.size.width / 8))
                .padding(.vertical, verticalPadding)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                .clipped()
        }
    }
}

/// This view draws one message. Expose that same view and its actual bounds as a static-text AX leaf.
final class PanelMessageHost: NSHostingView<PanelMessage> {
    override var isOpaque: Bool { false }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityIdentifier() -> String { rootView.style == .hint ? "panel.hint" : "panel.status" }
    override func accessibilityLabel() -> String? { rootView.message }
    override func accessibilityValue() -> Any? { rootView.message }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? { [] }

    required init(rootView: PanelMessage) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

struct PanelStatusMessage: NSViewRepresentable {
    let message: String
    func makeNSView(context: Context) -> PanelMessageHost {
        PanelMessageHost(rootView: PanelMessage(message: message, style: .status))
    }
    func updateNSView(_ view: PanelMessageHost, context: Context) {
        if view.rootView.message != message {
            view.rootView = PanelMessage(message: message, style: .status)
            NSAccessibility.post(element: view, notification: .valueChanged)
        }
    }
}
#endif
