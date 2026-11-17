import Foundation
import XCTest
@testable import IceCore

final class SourceFocusProgressTests: XCTestCase {
    private struct Recording: Decodable {
        let runID: UInt64
        let cases: [Case]
        struct Case: Decodable {
            let name: String
            let processID: Int32
            let windowID: UInt32
            let startedAt: Date
            let records: [Record]
        }
        struct Record: Decodable {
            let time: Date
            let observation: SourceFocusProgress.Observation
        }
    }

    private func recording(_ resource: String = "source-focus-observations") throws -> Recording {
        let url = try XCTUnwrap(Bundle.module.url(forResource: resource, withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Recording.self, from: Data(contentsOf: url))
    }

    func testRecordedWrongWindowNeverConfirms() throws {
        let recording = try recording()
        XCTAssertEqual(recording.runID, 43889327295)
        let value = try XCTUnwrap(recording.cases.first { $0.name == "minimized_hidden_restoration" })
        var progress = SourceFocusProgress(processID: value.processID, windowID: value.windowID, startedAt: 0)
        for record in value.records {
            XCTAssertFalse(progress.observe(record.observation, at: record.time.timeIntervalSince(value.startedAt)))
            XCTAssertEqual(progress.failure(for: record.observation), .keyboardFocus)
            XCTAssertFalse(progress.requiresApplicationActivation(for: record.observation))
        }
        XCTAssertTrue(progress.expired(at: 5))
    }

    func testPendingQueriesDoNotPostponeScheduledAttempts() {
        var progress = SourceFocusProgress(processID: 4543, windowID: 114, startedAt: 0)
        var attempts: [Int] = []
        for tick in 0..<200 {
            if progress.beginAttempt(at: Double(tick) / 40) { attempts.append(tick) }
            progress.pending()
        }
        XCTAssertEqual(attempts, Array(stride(from: 0, to: 200, by: 10)))
        XCTAssertFalse(progress.beginAttempt(at: 5))
    }

    func testRecordedTerminalIdentityRequiresStableConfirmation() throws {
        let value = try XCTUnwrap(try recording().cases.first { $0.name == "retained_terminal_return" })
        let record = try XCTUnwrap(value.records.first)
        let time = record.time.timeIntervalSince(value.startedAt)
        var progress = SourceFocusProgress(processID: value.processID, windowID: value.windowID, startedAt: 0)
        XCTAssertNil(progress.failure(for: record.observation))
        XCTAssertFalse(progress.observe(record.observation, at: time))
        XCTAssertFalse(progress.observe(record.observation, at: time + 0.05))
        XCTAssertTrue(progress.observe(record.observation, at: time + 0.101))
    }

    func testPendingResetsConfirmationWithoutDelayingNextAttempt() throws {
        let value = try XCTUnwrap(try recording().cases.first { $0.name == "retained_terminal_return" })
        let record = try XCTUnwrap(value.records.first)
        var progress = SourceFocusProgress(processID: value.processID, windowID: value.windowID, startedAt: 0)
        XCTAssertTrue(progress.beginAttempt(at: 0))
        XCTAssertFalse(progress.observe(record.observation, at: 0.01))
        progress.pending()
        XCTAssertFalse(progress.observe(record.observation, at: 0.12))
        XCTAssertFalse(progress.observe(record.observation, at: 0.17))
        XCTAssertTrue(progress.observe(record.observation, at: 0.221))
        XCTAssertTrue(progress.beginAttempt(at: 0.25))
    }

    func testConfirmationCannotSucceedAfterDeadline() throws {
        let value = try XCTUnwrap(try recording().cases.first { $0.name == "retained_terminal_return" })
        let record = try XCTUnwrap(value.records.first)
        var progress = SourceFocusProgress(processID: value.processID, windowID: value.windowID, startedAt: 0)
        XCTAssertFalse(progress.observe(record.observation, at: 4.95))
        XCTAssertFalse(progress.observe(record.observation, at: 5.051))
    }

    func testRecordedOffSpaceWindowRequiresActivationWithForegroundPIDAlreadyCorrect() throws {
        let recording = try recording("source-focus-off-space-observations")
        XCTAssertEqual(recording.runID, 43893838209)
        let value = try XCTUnwrap(recording.cases.first)
        var progress = SourceFocusProgress(processID: value.processID, windowID: value.windowID, startedAt: 0)
        for record in value.records {
            XCTAssertTrue(progress.requiresApplicationActivation(for: record.observation))
            XCTAssertEqual(progress.failure(for: record.observation), .space)
            XCTAssertFalse(progress.observe(record.observation, at: record.time.timeIntervalSince(value.startedAt)))
        }
        let final = try XCTUnwrap(value.records.last)
        XCTAssertEqual(final.observation.foregroundPID, value.processID)
        XCTAssertEqual(final.observation.focusedWindowID, value.windowID)
    }

    func testRecordedVisibleExactWindowDoesNotRepeatBroadActivation() throws {
        let value = try XCTUnwrap(try recording().cases.first { $0.name == "retained_terminal_return" })
        let record = try XCTUnwrap(value.records.first)
        let progress = SourceFocusProgress(processID: value.processID, windowID: value.windowID, startedAt: 0)
        XCTAssertFalse(progress.requiresApplicationActivation(for: record.observation))
    }
}
