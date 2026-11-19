// Shared by the native test driver and its platform-independent regression tests.
struct RestoredFocusSample {
    let frontmostPID: Int32?
    let frontmostBundle: String?
    let active: Bool
    let hidden: Bool
    let focusedWindowID: UInt32?

    enum Verdict: Equatable {
        case pending(String), wrongWindow(String), confirmed
    }

    func verdict(expectedPID: Int32, windowID: UInt32) -> Verdict {
        let details = "expectedPID=\(expectedPID) expectedWindow=\(windowID) " +
            "frontmostPID=\(frontmostPID.map(String.init) ?? "nil") frontmostBundle=\(frontmostBundle ?? "nil") " +
            "active=\(active) hidden=\(hidden) targetFocusedWindow=\(focusedWindowID.map(String.init) ?? "nil")"
        guard active, !hidden, frontmostPID == expectedPID else { return .pending(details) }
        guard focusedWindowID == windowID else { return .wrongWindow(details) }
        return .confirmed
    }
}
