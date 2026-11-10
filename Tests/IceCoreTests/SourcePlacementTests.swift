import XCTest
@testable import IceCore

final class SourcePlacementTests: XCTestCase {
    func testParkingClearsEveryDisplayIncludingNegativeOrigins() throws {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -120, width: 1920, height: 1080)]
        let original = CGRect(x: 180, y: 120, width: 800, height: 600)
        let parked = try XCTUnwrap(SourcePlacement.parkedFrame(original, screens: screens))
        XCTAssertEqual(parked.size, original.size)
        XCTAssertEqual(parked.origin, CGPoint(x: 1450, y: 910))
        XCTAssertEqual(SourcePlacement.visibleArea(parked, screens: screens), 0)
        XCTAssertEqual(SourcePlacement.restoredFrame(original, screens: screens), original)
        let spanning = CGRect(x: -400, y: 160, width: 800, height: 600)
        XCTAssertEqual(SourcePlacement.restoredFrame(spanning, screens: screens), spanning)
    }
    func testParkingAvoidsDisplaysBelowAndAlongsideTheSource() throws {
        let sourceDisplay = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let layouts = [
            [sourceDisplay, CGRect(x: 1440, y: 0, width: 1920, height: 1080)],
            [sourceDisplay, CGRect(x: -400, y: 900, width: 1920, height: 1080)],
            [sourceDisplay, CGRect(x: -1920, y: -1080, width: 1920, height: 1080)],
            [sourceDisplay, CGRect(x: -1920, y: 900, width: 1920, height: 1080),
             CGRect(x: 1440, y: 0, width: 1920, height: 2160)]
        ]
        let original = CGRect(x: 180, y: 120, width: 800, height: 600)
        for screens in layouts {
            let destinations = SourcePlacement.parkingDestinations(original, screens: screens)
            XCTAssertFalse(destinations.isEmpty)
            for destination in destinations {
                XCTAssertEqual(destination.size, original.size)
                XCTAssertEqual(SourcePlacement.visibleArea(destination, screens: screens), 0)
                XCTAssertTrue(SourcePlacement.isOutsideDisplays(destination, screens: screens))
            }
        }
        let destinations = SourcePlacement.parkingDestinations(original, screens: layouts[0])
        XCTAssertEqual(try XCTUnwrap(destinations.first).origin, CGPoint(x: -810, y: 910))
    }
    func testParkingStartsNearTheSourcesDisplay() throws {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: -1080, width: 1920, height: 1080)]
        let original = CGRect(x: -1400, y: -900, width: 800, height: 600)
        let destination = try XCTUnwrap(SourcePlacement.parkedFrame(original, screens: screens))
        XCTAssertEqual(destination.origin, CGPoint(x: -2730, y: 10))
        XCTAssertTrue(SourcePlacement.isOutsideDisplays(destination, screens: screens))
    }
    func testParkingRejectsInvalidGeometry() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 180, y: 120, width: 800, height: 600)
        for invalid in [CGRect.zero, .null, .infinite, CGRect(x: CGFloat.nan, y: 0, width: 800, height: 600)] {
            XCTAssertTrue(SourcePlacement.parkingDestinations(invalid, screens: [screen]).isEmpty)
            XCTAssertTrue(SourcePlacement.parkingDestinations(window, screens: [invalid]).isEmpty)
            XCTAssertFalse(SourcePlacement.isOutsideDisplays(invalid, screens: [screen]))
            XCTAssertFalse(SourcePlacement.isOutsideDisplays(window, screens: [invalid]))
        }
        XCTAssertNil(SourcePlacement.parkedFrame(window, screens: []))
        XCTAssertFalse(SourcePlacement.isOutsideDisplays(window, screens: []))
    }
    func testWindowConstrainedToVisibleStripDoesNotCountAsParked() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertFalse(SourcePlacement.isOutsideDisplays(CGRect(x: -760, y: 120, width: 800, height: 600), screens: [screen]))
        XCTAssertFalse(SourcePlacement.isOutsideDisplays(CGRect(x: 180, y: 875, width: 800, height: 600), screens: [screen]))
        XCTAssertTrue(SourcePlacement.isOutsideDisplays(CGRect(x: -799, y: 120, width: 800, height: 600), screens: [screen]))
        XCTAssertTrue(SourcePlacement.isOutsideDisplays(CGRect(x: 180, y: 901, width: 800, height: 600), screens: [screen]))
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
