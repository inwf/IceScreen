import XCTest
@testable import IceCore

final class PinchZoomTests: XCTestCase {
    func testPinchAccumulatesNativeDeltasWithoutExponentialDrift() {
        var gesture = PinchZoomGesture()
        gesture.begin(viewport: .full, anchor: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(gesture.change(by: 0.2)!.magnification, 1.2, accuracy: 0.000001)
        XCTAssertEqual(gesture.change(by: 0.3)!.magnification, 1.5, accuracy: 0.000001)
        XCTAssertEqual(gesture.change(by: -0.5)!, .full)
    }

    func testPinchInAndOutFromAnExistingRegionPreservesItsAspectRatio() {
        let original = Viewport(rect: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2))
        var gesture = PinchZoomGesture()
        gesture.begin(viewport: original, anchor: CGPoint(x: 0.5, y: 0.5))
        let enlarged = gesture.change(by: 0.5)!
        XCTAssertLessThan(enlarged.rect.width, original.rect.width)
        XCTAssertEqual(enlarged.rect.width / enlarged.rect.height, 2, accuracy: 0.000001)
        let reduced = gesture.change(by: -0.75)!
        XCTAssertGreaterThan(reduced.rect.width, original.rect.width)
        XCTAssertEqual(reduced.rect.width / reduced.rect.height, 2, accuracy: 0.000001)
    }

    func testPinchKeepsTheStartingSourcePointAtTheSamePosition() {
        let initial = Viewport.initial(anchor: .center, factor: 2)
        let anchor = CGPoint(x: 0.2, y: 0.8)
        var gesture = PinchZoomGesture()
        gesture.begin(viewport: initial, anchor: anchor)
        for delta in [0.2, 0.15, -0.1, 0.4] {
            let viewport = gesture.change(by: delta)!
            XCTAssertEqual(initial.rect.minX + anchor.x * initial.rect.width,
                           viewport.rect.minX + anchor.x * viewport.rect.width, accuracy: 0.000001)
            XCTAssertEqual(initial.rect.minY + anchor.y * initial.rect.height,
                           viewport.rect.minY + anchor.y * viewport.rect.height, accuracy: 0.000001)
        }
    }

    func testReversingAtZoomLimitsRespondsImmediately() {
        var gesture = PinchZoomGesture()
        gesture.begin(viewport: .full, anchor: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(gesture.change(by: -100)!, .full)
        XCTAssertGreaterThan(gesture.change(by: 0.1)!.magnification, 1)
        XCTAssertEqual(gesture.change(by: 100)!.magnification, 32)
        XCTAssertLessThan(gesture.change(by: -0.1)!.magnification, 32)
    }

    func testEndingOrCancellingPreventsLateChangesAndResetsTheNextGesture() {
        var gesture = PinchZoomGesture()
        XCTAssertNil(gesture.change(by: 0.5))
        gesture.begin(viewport: .full, anchor: CGPoint(x: 0.5, y: 0.5))
        let previous = gesture.change(by: 1)!
        gesture.end()
        XCTAssertFalse(gesture.isActive)
        XCTAssertNil(gesture.change(by: 10))
        gesture.begin(viewport: previous, anchor: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(gesture.change(by: 0.25)!.magnification, 2.5, accuracy: 0.000001)
    }

    func testInvalidDeltasDoNotCorruptTheNextFrame() {
        var gesture = PinchZoomGesture()
        gesture.begin(viewport: .full, anchor: CGPoint(x: Double.nan, y: Double.infinity))
        for delta in [Double.nan, .infinity, -.infinity] { XCTAssertNil(gesture.change(by: delta)) }
        XCTAssertEqual(gesture.change(by: 1), .initial(anchor: .center, factor: 2))
    }

    func testRepeatedPinchesStayWithinTheSource() {
        var viewport = Viewport.full
        var gesture = PinchZoomGesture()
        for index in 0..<200 {
            gesture.begin(viewport: viewport, anchor: CGPoint(x: Double(index % 10) / 9, y: Double(index % 7) / 6))
            for delta in [0.1, 0.4, -0.7, 0.2] {
                viewport = gesture.change(by: delta)!
                XCTAssertGreaterThanOrEqual(viewport.rect.minX, 0)
                XCTAssertGreaterThanOrEqual(viewport.rect.minY, 0)
                XCTAssertLessThanOrEqual(viewport.rect.maxX, 1.000001)
                XCTAssertLessThanOrEqual(viewport.rect.maxY, 1.000001)
                XCTAssertGreaterThanOrEqual(min(viewport.rect.width, viewport.rect.height), 1 / 32.0)
            }
            gesture.end()
        }
    }
}
