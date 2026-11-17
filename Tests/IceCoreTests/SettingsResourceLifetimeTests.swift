import XCTest
@testable import IceCore

final class SettingsResourceLifetimeTests: XCTestCase {
    @MainActor
    func testClosedResourcesReleaseOnceAfterDelay() async throws {
        var releases = 0
        let lifetime = SettingsResourceLifetime(delay: .milliseconds(30)) { releases += 1 }
        lifetime.opened()
        lifetime.closed()
        XCTAssertEqual(releases, 0)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(releases, 1)
        lifetime.closed()
        lifetime.memoryPressureChanged(isElevated: true)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(releases, 1)
    }

    @MainActor
    func testReopeningCancelsOldReleaseAndNextCloseSchedulesAnother() async throws {
        var releases = 0
        let lifetime = SettingsResourceLifetime(delay: .milliseconds(30)) { releases += 1 }
        lifetime.opened()
        lifetime.closed()
        lifetime.opened()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(releases, 0)
        lifetime.closed()
        XCTAssertEqual(releases, 0)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(releases, 1)
        lifetime.opened()
        lifetime.closed()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(releases, 2)
    }

    @MainActor
    func testMemoryPressureReleasesClosedResourcesBeforeDeadline() async throws {
        var releases = 0
        let lifetime = SettingsResourceLifetime { releases += 1 }
        lifetime.opened()
        lifetime.closed()
        lifetime.memoryPressureChanged(isElevated: true)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(releases, 1)
    }

    @MainActor
    func testMemoryPressureProtectsOpenResourcesAndAppliesAtClose() async throws {
        var releases = 0
        let lifetime = SettingsResourceLifetime { releases += 1 }
        lifetime.memoryPressureChanged(isElevated: true)
        lifetime.opened()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(releases, 0)
        lifetime.closed()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(releases, 1)
    }

    @MainActor
    func testRecoveredPressureAndCancelledPressureReleaseKeepResources() async throws {
        var releases = 0
        let lifetime = SettingsResourceLifetime { releases += 1 }
        lifetime.opened()
        lifetime.memoryPressureChanged(isElevated: true)
        lifetime.closed()
        lifetime.opened()
        lifetime.memoryPressureChanged(isElevated: false)
        lifetime.closed()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(releases, 0)
    }

    @MainActor
    func testPendingTaskDoesNotRetainLifetimeOwner() async throws {
        var releases = 0
        var lifetime: SettingsResourceLifetime? = SettingsResourceLifetime(delay: .milliseconds(30)) { releases += 1 }
        weak var weakLifetime = lifetime
        lifetime?.opened()
        lifetime?.closed()
        lifetime = nil
        XCTAssertNil(weakLifetime)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(releases, 0)
    }
}
