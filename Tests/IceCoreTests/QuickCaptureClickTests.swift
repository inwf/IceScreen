import XCTest
@testable import IceCore

final class QuickCaptureClickTests: XCTestCase {
    func testCustomCombinationRequiresAnExactMatchForBothClicks() {
        let combination: QuickCaptureModifiers = [.command, .shift]
        for held: QuickCaptureModifiers in [[], .command, .shift, [.command, .shift, .option], .function] {
            XCTAssertFalse(combination.matches(held))
            var gate = QuickCaptureClickGate<Int>(interval: 0.5)
            XCTAssertFalse(gate.handle(.down, event: 1, at: 0, position: .zero, eligible: combination.matches(held)).consume)
        }
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        XCTAssertTrue(gate.handle(.down, event: 1, at: 0, position: .zero, eligible: combination.matches([.command, .shift])).consume)
        _ = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: combination.matches([.command, .shift]))
        let changed = gate.handle(.down, event: 3, at: 0.2, position: .zero,
                                  eligible: combination.matches([.command, .shift, .option]), clickCount: 2)
        XCTAssertFalse(changed.capture || changed.consume)
        XCTAssertEqual(changed.replay, [1, 2])
        XCTAssertFalse(QuickCaptureModifiers().matches([]))
    }

    func testModifierRecordingWaitsForReleaseAndKeepsTheFullChord() {
        var recording = ModifierChordRecording()
        XCTAssertNil(recording.update(.command))
        XCTAssertNil(recording.update([.command, .shift]))
        XCTAssertNil(recording.update(.shift))
        XCTAssertEqual(recording.update([]), [.command, .shift])
        XCTAssertNil(recording.update([]))
        XCTAssertNil(recording.update(.function))
        recording.reset()
        XCTAssertNil(recording.update([]))
        _ = recording.update([.command, .shift])
        recording.rejectUntilRelease()
        XCTAssertNil(recording.update(.command))
        XCTAssertNil(recording.update([]))
        XCTAssertNil(recording.update(.option))
        XCTAssertEqual(recording.update([]), .option)
    }

    func testQuickCaptureCombinationMigratesAndPersistsIndependently() throws {
        for modifier in TriggerModifier.allCases {
            let data = Data("{\"triggerModifier\":\"\(modifier.rawValue)\"}".utf8)
            var preferences = try JSONDecoder().decode(Preferences.self, from: data)
            XCTAssertEqual(preferences.quickCaptureModifiers, QuickCaptureModifiers(trigger: modifier))
            preferences.quickCaptureModifiers = [.command, .shift]
            preferences.triggerModifier = .option
            let saved = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
            XCTAssertEqual(saved.quickCaptureModifiers, [.command, .shift])
            XCTAssertEqual(saved.triggerModifier, .option)
            preferences.quickCaptureModifiers = []
            preferences.normalize()
            XCTAssertEqual(preferences.quickCaptureModifiers, .option)
        }
        XCTAssertEqual(Preferences().quickCaptureModifiers, .function)
    }

    func testCaptureConsumesBothClicksIncludingTheFinalRelease() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        let first = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        XCTAssertTrue(first.consume)
        XCTAssertFalse(first.capture)
        XCTAssertTrue(first.replay.isEmpty)
        let release = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: true)
        XCTAssertTrue(release.consume)
        XCTAssertTrue(release.replay.isEmpty)
        let second = gate.handle(.down, event: 3, at: 0.2, position: .zero, eligible: true, clickCount: 2)
        XCTAssertTrue(second.consume && second.capture)
        XCTAssertTrue(second.replay.isEmpty)
        XCTAssertNil(gate.deadline)
        XCTAssertTrue(gate.handle(.dragged, event: 4, at: 0.3, position: CGPoint(x: 20, y: 0), eligible: false).consume)
        XCTAssertTrue(gate.handle(.up, event: 5, at: 0.4, position: .zero, eligible: false).consume)
        XCTAssertTrue(gate.expire(at: 1).isEmpty)
        XCTAssertFalse(gate.handle(.down, event: 6, at: 2, position: .zero, eligible: false).consume)
    }

    func testSingleClickIsDeliveredOnceInOriginalOrderAfterTheInterval() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 10, position: .zero, eligible: true)
        _ = gate.handle(.up, event: 2, at: 10.1, position: .zero, eligible: true)
        XCTAssertTrue(gate.expire(at: 10.49).isEmpty)
        XCTAssertEqual(gate.expire(at: 10.5), [1, 2])
        XCTAssertTrue(gate.expire(at: 11).isEmpty)
        XCTAssertNil(gate.deadline)
    }

    func testDragReleasesThePressBeforeForwardingMovementAndRelease() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        let drag = gate.handle(.dragged, event: 2, at: 0.05, position: CGPoint(x: 8, y: 0), eligible: true)
        XCTAssertEqual(drag.replay, [1])
        XCTAssertFalse(drag.consume || drag.capture)
        XCTAssertNil(gate.deadline)
        XCTAssertFalse(gate.handle(.up, event: 3, at: 0.1, position: CGPoint(x: 8, y: 0), eligible: true).consume)
    }

    func testPointerJitterDoesNotLeakTheFirstClick() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        let jitter = gate.handle(.dragged, event: 2, at: 0.03, position: CGPoint(x: 1, y: 1), eligible: true)
        XCTAssertTrue(jitter.consume)
        XCTAssertTrue(jitter.replay.isEmpty)
        _ = gate.handle(.up, event: 3, at: 0.05, position: CGPoint(x: 1, y: 1), eligible: true)
        let capture = gate.handle(.down, event: 4, at: 0.2, position: CGPoint(x: 2, y: 0), eligible: true, clickCount: 2)
        XCTAssertTrue(capture.capture)
        XCTAssertTrue(capture.replay.isEmpty)
    }

    func testUnmodifiedAndDisabledClicksAreNeverDelayed() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        for count in [1, 2] {
            let down = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: false, clickCount: count)
            XCTAssertFalse(down.consume || down.capture)
            XCTAssertFalse(gate.handle(.up, event: 2, at: 0.1, position: .zero, eligible: false).consume)
        }
        XCTAssertNil(gate.deadline)
    }

    func testModifierAddedOnlyForSecondClickCannotCapture() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: false)
        _ = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: false)
        let second = gate.handle(.down, event: 3, at: 0.2, position: .zero, eligible: true, clickCount: 2)
        XCTAssertFalse(second.consume || second.capture)
    }

    func testKeyboardOrModifierChangeReleasesPendingClickBeforeTheNewInput() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        _ = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: true)
        let interrupted = gate.handle(.interrupt, event: 3, at: 0.1, position: .zero, eligible: false)
        XCTAssertEqual(interrupted.replay, [1, 2])
        XCTAssertFalse(interrupted.consume)
        let second = gate.handle(.down, event: 4, at: 0.2, position: .zero, eligible: true, clickCount: 2)
        XCTAssertFalse(second.capture)
    }

    func testLongPressIsReleasedAtDeadlineAndItsMouseUpPassesThrough() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        XCTAssertEqual(gate.expire(at: 0.5), [1])
        XCTAssertFalse(gate.handle(.up, event: 2, at: 1, position: .zero, eligible: true).consume)
    }

    func testDeadlineAlsoAppliesBeforeTheTimerGetsToRun() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        _ = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: true)
        let late = gate.handle(.down, event: 3, at: 0.51, position: .zero, eligible: true, clickCount: 2)
        XCTAssertEqual(late.replay, [1, 2])
        XCTAssertFalse(late.capture || late.consume)
    }

    func testDistantSecondClickCannotCaptureAndReplaysTheFirst() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        _ = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: true)
        let far = gate.handle(.down, event: 3, at: 0.2, position: CGPoint(x: 100, y: 0), eligible: true, clickCount: 2)
        XCTAssertEqual(far.replay, [1, 2])
        XCTAssertFalse(far.capture || far.consume)
    }

    func testSettingsChangeDoesNotLeakTheCapturedMouseUp() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        _ = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: true)
        _ = gate.handle(.down, event: 3, at: 0.2, position: .zero, eligible: true, clickCount: 2)
        XCTAssertTrue(gate.flush().isEmpty)
        XCTAssertTrue(gate.handle(.up, event: 4, at: 0.3, position: .zero, eligible: false).consume)
    }

    func testStoppingWithPendingInputReleasesItExactlyOnce() {
        var gate = QuickCaptureClickGate<Int>(interval: 0.5)
        _ = gate.handle(.down, event: 1, at: 0, position: .zero, eligible: true)
        _ = gate.handle(.up, event: 2, at: 0.05, position: .zero, eligible: true)
        XCTAssertEqual(gate.reset(), [1, 2])
        XCTAssertTrue(gate.reset().isEmpty)
        XCTAssertNil(gate.deadline)
    }
}
