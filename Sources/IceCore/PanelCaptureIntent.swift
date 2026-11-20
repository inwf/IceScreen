/// How the panel was requested, independent of its current zoom or crop.
public enum PanelCaptureIntent: Equatable, Sendable {
    case window, region

    public enum Match: Equatable { case ignore, reuse, close }

    /// Called only for panels belonging to the requested source window.
    public func match(existing: Self, multiple: Bool, toggleExisting: Bool) -> Match {
        if multiple && (self == .region || existing != .window) { return .ignore }
        if self == .window && existing == .window && toggleExisting { return .close }
        return .reuse
    }
}
