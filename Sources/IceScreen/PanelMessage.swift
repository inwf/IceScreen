#if os(macOS)
import AppKit
import SwiftUI

struct PanelMessage: View {
    enum Style { case hint, status }
    let message: String
    let style: Style

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
            if style == .status {
                label.foregroundStyle(.white)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            } else if #available(macOS 26.0, *) {
                label.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            } else {
                label.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityIdentifier(style == .hint ? "panel.hint" : "panel.status")
        .accessibilityAddTraits(.updatesFrequently)
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
#endif
