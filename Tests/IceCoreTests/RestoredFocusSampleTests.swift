import XCTest

final class RestoredFocusSampleTests: XCTestCase {
    // PIDs and window ID from the failed Terminal check; recovery is simulated.
    private let terminal: Int32 = 7110
    private let window: UInt32 = 75
    private let notification = RestoredFocusSample(frontmostPID: 7151, frontmostBundle: "com.apple.UserNotificationCenter",
                                                  active: false, hidden: false, focusedWindowID: 75)

    func testTransientInterruptionWaitsForExactTerminalWindow() {
        let recovered = RestoredFocusSample(frontmostPID: terminal, frontmostBundle: "com.apple.Terminal",
                                            active: true, hidden: false, focusedWindowID: window)
        let samples = [notification, notification, recovered]
        XCTAssertEqual(samples.firstIndex { $0.verdict(expectedPID: terminal, windowID: window) == .confirmed }, 2)
    }

    func testPersistentlyInterruptedWindowStaysPendingWithIdentitiesForTimeout() {
        guard case let .pending(details) = notification.verdict(expectedPID: terminal, windowID: window)
        else { return XCTFail("The background application's AX focus alone cannot confirm a return.") }
        for field in ["expectedPID=7110", "frontmostPID=7151", "com.apple.UserNotificationCenter", "targetFocusedWindow=75"] {
            XCTAssertTrue(details.contains(field))
        }
    }

    func testForegroundTerminalWithWrongWindowFails() {
        let wrong = RestoredFocusSample(frontmostPID: terminal, frontmostBundle: "com.apple.Terminal",
                                        active: true, hidden: false, focusedWindowID: 115)
        guard case let .wrongWindow(details) = wrong.verdict(expectedPID: terminal, windowID: window)
        else { return XCTFail("The foreground PID alone cannot confirm the window.") }
        XCTAssertTrue(details.contains("expectedWindow=75"))
        XCTAssertTrue(details.contains("targetFocusedWindow=115"))
    }
}
