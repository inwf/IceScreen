import XCTest
@testable import IceCore

final class SourcePlacementTests: XCTestCase {
    func testParkingClearsEveryDisplayIncludingNegativeOrigins() throws {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -120, width: 1920, height: 1080)]
        let original = CGRect(x: 180, y: 120, width: 800, height: 600)
        let parked = try XCTUnwrap(SourcePlacement.parkedFrame(original, screens: screens))
        XCTAssertEqual(parked.size, original.size)
        XCTAssertEqual(parked.minY, original.minY)
        XCTAssertEqual(SourcePlacement.visibleArea(parked, screens: screens), 0)
        XCTAssertEqual(SourcePlacement.restoredFrame(original, screens: screens), original)
        let spanning = CGRect(x: -400, y: 160, width: 800, height: 600)
        XCTAssertEqual(SourcePlacement.restoredFrame(spanning, screens: screens), spanning)
    }
    func testRestoreAfterDisplayDisconnectClampsToRemainingScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let original = CGRect(x: -1800, y: -120, width: 1600, height: 1000)
        XCTAssertEqual(SourcePlacement.restoredFrame(original, screens: [screen]), screen)
    }
    func testStageThumbnailDistinguishedFromSmallAndParkedWindows() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let thumbnail = CGRect(x: -15, y: 200, width: 140, height: 110)
        let full = CGSize(width: 800, height: 600)
        XCTAssertTrue(StageManagerGeometry.isInactive(enabled: true, frame: thumbnail, fullSize: full, screens: [screen], intentionallyParked: false))
        XCTAssertFalse(StageManagerGeometry.isInactive(enabled: false, frame: thumbnail, fullSize: full, screens: [screen], intentionallyParked: false))
        XCTAssertFalse(StageManagerGeometry.isInactive(enabled: true, frame: thumbnail, fullSize: full, screens: [screen], intentionallyParked: true))
        XCTAssertFalse(StageManagerGeometry.isInactive(enabled: true, frame: thumbnail, fullSize: thumbnail.size, screens: [screen], intentionallyParked: false))
        XCTAssertFalse(StageManagerGeometry.isInactive(enabled: true, frame: thumbnail.offsetBy(dx: 600, dy: 0), fullSize: full, screens: [screen], intentionallyParked: false))
    }
}
