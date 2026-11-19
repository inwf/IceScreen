import XCTest
import IceCore

final class PanelCaptureIntentTests: XCTestCase {
    func testEveryRegionRequestGetsANewPanelInMultipleMode() {
        for existing in [PanelCaptureIntent.region, .window] {
            for hidden in [true, false] {
                XCTAssertEqual(PanelCaptureIntent.region.match(existing: existing, multiple: true, toggleExisting: false, hidden: hidden), .ignore)
            }
        }
    }

    func testWindowHotkeySkipsRegionsAndTogglesOnlyItsWindowPanel() {
        let intent = PanelCaptureIntent.window
        XCTAssertEqual(intent.match(existing: .region, multiple: true, toggleExisting: true, hidden: false), .ignore)
        XCTAssertEqual(intent.match(existing: .window, multiple: true, toggleExisting: true, hidden: false), .close)
        XCTAssertEqual(intent.match(existing: .window, multiple: true, toggleExisting: true, hidden: true), .reuse)
        XCTAssertEqual(intent.match(existing: .window, multiple: true, toggleExisting: false, hidden: false), .reuse)
    }

    func testSingleModeReusesPanelWhenChangingCaptureKind() {
        XCTAssertEqual(PanelCaptureIntent.region.match(existing: .region, multiple: false, toggleExisting: false, hidden: false), .reuse)
        XCTAssertEqual(PanelCaptureIntent.region.match(existing: .window, multiple: false, toggleExisting: false, hidden: false), .reuse)
        XCTAssertEqual(PanelCaptureIntent.window.match(existing: .region, multiple: false, toggleExisting: true, hidden: false), .reuse)
    }
}
