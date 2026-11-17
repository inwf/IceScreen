import Foundation

public struct PanelMessageLayout: Equatable, Sendable {
    public let message: CGRect
    public let action: CGRect?

    public init(in bounds: CGRect, messageSize: CGSize, actionSize: CGSize? = nil, spacing: CGFloat = 8) {
        let width = max(0, bounds.width), height = max(0, bounds.height)
        let button = actionSize.map { CGSize(width: min(width, max(0, $0.width)), height: min(height, max(0, $0.height))) }
        let gap = button == nil ? 0 : min(max(0, spacing), max(0, height - button!.height))
        let text = CGSize(width: min(width, max(0, messageSize.width)),
                          height: min(max(0, height - (button?.height ?? 0) - gap), max(0, messageSize.height)))
        let top = bounds.midY - (text.height + gap + (button?.height ?? 0)) / 2
        message = CGRect(x: bounds.midX - text.width / 2, y: top, width: text.width, height: text.height)
        action = button.map { CGRect(x: bounds.midX - $0.width / 2, y: top + text.height + gap, width: $0.width, height: $0.height) }
    }
}
