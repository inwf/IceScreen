import XCTest
@testable import IceCore

final class MediaPlaybackTests: XCTestCase {
    private func track(_ id: String = "track", pid: Int32 = 42, bundle: String = "org.player", title: String = "Title") -> MediaSnapshot {
        .init(id: id, pid: pid, bundleID: bundle, title: title, duration: 90, elapsed: 10, timestamp: 100, rate: 1, canSeek: true)
    }
    func testTimeInterpolationAndSeekingBounds() {
        let value = track()
        XCTAssertEqual(value.position(at: 105), 15)
        XCTAssertEqual(value.position(at: 200), 90)
        XCTAssertEqual(value.seekPosition(relative: -30, at: 105), 0)
        XCTAssertEqual(value.seekPosition(relative: 300, at: 105), 90)
        var live = value; live.duration = nil
        XCTAssertFalse(live.seekable)
        XCTAssertNil(live.seekPosition(relative: 5, at: 105))
        var paused = value; paused.rate = 0
        XCTAssertEqual(paused.position(at: 105), 10)
    }
    func testNewSettingsMigrateAndPersistExplicitChoices() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.mediaControls && legacy.mediaSeek && legacy.mediaSpace && legacy.smartRegionCapture && legacy.moveSourceOffscreen)
        var changed = legacy
        changed.mediaControls = false; changed.mediaSeek = false; changed.mediaSpace = false
        changed.smartRegionCapture = false; changed.moveSourceOffscreen = false
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(changed)), changed)
    }
    func testMatchingNeverChoosesUnrelatedOrAmbiguousPlayer() {
        let values = [track(), track("other", pid: 43, bundle: "org.other")]
        XCTAssertEqual(MediaSnapshot.match(values, pid: 42, bundleID: "org.player", title: "Title")?.id, "track")
        XCTAssertNil(MediaSnapshot.match(values, pid: 50, bundleID: "org.unknown", title: "Title"))
        XCTAssertNil(MediaSnapshot.match([track(), track("another")], pid: 42, bundleID: "org.player", title: "Title"))
    }
    func testSpaceTapHoldAndCancellationAreMutuallyExclusive() {
        var gesture = MediaSpaceGesture()
        gesture.press(at: 1)
        XCTAssertFalse(gesture.hold(at: 1.1))
        XCTAssertTrue(gesture.release(at: 1.2))
        gesture.press(at: 2)
        XCTAssertTrue(gesture.hold(at: 2.3))
        XCTAssertFalse(gesture.hold(at: 2.4))
        XCTAssertFalse(gesture.release(at: 2.5))
        gesture.press(at: 3); gesture.cancel()
        XCTAssertFalse(gesture.release(at: 3.1))
        gesture.press(at: 4)
        XCTAssertFalse(gesture.release(at: 4.3))
    }
}
