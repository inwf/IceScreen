import XCTest
import IceCore

final class PanelCaptureIntentTests: XCTestCase {
    func testEveryRegionRequestGetsANewPanelInMultipleMode() {
        for existing in [PanelCaptureIntent.region, .window] {
            XCTAssertEqual(PanelCaptureIntent.region.match(existing: existing, multiple: true, toggleExisting: false), .ignore)
        }
    }

    func testWindowHotkeySkipsRegionsAndTogglesOnlyItsWindowPanel() {
        let intent = PanelCaptureIntent.window
        XCTAssertEqual(intent.match(existing: .region, multiple: true, toggleExisting: true), .ignore)
        XCTAssertEqual(intent.match(existing: .window, multiple: true, toggleExisting: true), .close)
        XCTAssertEqual(intent.match(existing: .window, multiple: true, toggleExisting: false), .reuse)
    }

    func testSingleModeReusesPanelWhenChangingCaptureKind() {
        XCTAssertEqual(PanelCaptureIntent.region.match(existing: .region, multiple: false, toggleExisting: false), .reuse)
        XCTAssertEqual(PanelCaptureIntent.region.match(existing: .window, multiple: false, toggleExisting: false), .reuse)
        XCTAssertEqual(PanelCaptureIntent.window.match(existing: .region, multiple: false, toggleExisting: true), .reuse)
    }
}
