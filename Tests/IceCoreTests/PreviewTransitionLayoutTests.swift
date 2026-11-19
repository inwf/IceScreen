import XCTest
@testable import IceCore

final class PreviewTransitionLayoutTests: XCTestCase {
    func testOvershootFollowsApproachFromAllCornersAndDoesNotDriftAtCenter() {
        let target = CGPoint(x: -80, y: 240)
        for dx in [-1200.0, 12.0] {
            for dy in [-900.0, 10.0] {
                let start = CGPoint(x: target.x - dx, y: target.y - dy)
                let peak = PreviewTransitionLayout.overshoot(from: start, to: target)
                let x = peak.x - target.x, y = peak.y - target.y
                XCTAssertGreaterThan(x * dx + y * dy, 0)
                XCTAssertEqual(x * dy, y * dx, accuracy: 1e-8)
                XCTAssertLessThanOrEqual(hypot(x, y), 8.000001)
            }
        }
        XCTAssertEqual(PreviewTransitionLayout.overshoot(from: target, to: target), target)
    }

    let preview = CGSize(width: 800, height: 400)

    func testFullFrameOnSecondaryDisplay() throws {
        let panel = CGRect(x: -1240, y: -60, width: 200, height: 100)
        let layout = try XCTUnwrap(PreviewTransitionLayout(panel: panel, previewSize: preview, viewport: .full))
        XCTAssertEqual(layout.thumbnail, panel)
        XCTAssertEqual(layout.image, CGRect(origin: .zero, size: panel.size))
    }

    func testOffCenterCropMapsExactlyIntoThumbnail() throws {
        let crop = Viewport(rect: CGRect(x: 0.5, y: 0, width: 0.25, height: 0.5))
        let panel = CGRect(x: 10, y: 30, width: 110, height: 100)
        let layout = try XCTUnwrap(PreviewTransitionLayout(panel: panel, previewSize: preview, viewport: crop))
        XCTAssertEqual(layout.thumbnail, CGRect(x: 15, y: 30, width: 100, height: 100))
        XCTAssertEqual(layout.image, CGRect(x: -200, y: -100, width: 400, height: 200))
    }

    func testBottomCropUsesBottomOfImageAndInvalidGeometryFallsBack() throws {
        let panel = CGRect(x: 110, y: 50, width: 200, height: 50)
        let crop = Viewport(rect: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        let layout = try XCTUnwrap(PreviewTransitionLayout(panel: panel, previewSize: preview, viewport: crop))
        XCTAssertEqual(layout.image, CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertNil(PreviewTransitionLayout(panel: .zero, previewSize: preview, viewport: crop))
        XCTAssertNil(PreviewTransitionLayout(panel: panel, previewSize: .zero, viewport: crop))
    }
}
