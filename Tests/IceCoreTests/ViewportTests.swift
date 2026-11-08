import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import IceCore

final class ViewportTests: XCTestCase {
    func testAllZoomAnchorsRemainAtTheirEdges() {
        for anchor in ZoomAnchor.allCases {
            let viewport = Viewport.initial(anchor: anchor, factor: 4)
            XCTAssertEqual(viewport.rect.width, 0.25, accuracy: 0.000001)
            XCTAssertEqual(viewport.rect.minX, 0.75 * anchor.point.x, accuracy: 0.000001)
            XCTAssertEqual(viewport.rect.minY, 0.75 * anchor.point.y, accuracy: 0.000001)
        }
    }

    func testNestedSelectionMapsIntoOriginalWindow() {
        let first = Viewport(rect: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25))
        let next = first.selecting(CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        XCTAssertEqual(next.rect, CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.125))
        XCTAssertEqual(next.sourceRect(in: CGSize(width: 1600, height: 900)),
                       CGRect(x: 800, y: 450, width: 400, height: 112.5))
    }

    func testPanClampsAtWindowEdges() {
        let initial = Viewport.initial(anchor: .center, factor: 4)
        XCTAssertEqual(initial.panned(x: 100, y: -100).rect, CGRect(x: 0.75, y: 0, width: 0.25, height: 0.25))
        XCTAssertEqual(Viewport.full.panned(x: 5, y: -5), .full)
    }

    func testZoomAroundPointerKeepsSourcePointStationary() {
        let old = Viewport.initial(anchor: .center, factor: 2)
        let pointer = CGPoint(x: 0.2, y: 0.7)
        let new = old.zoomed(by: 2, around: pointer)
        XCTAssertEqual(old.rect.minX + pointer.x * old.rect.width,
                       new.rect.minX + pointer.x * new.rect.width, accuracy: 0.000001)
        XCTAssertEqual(old.rect.minY + pointer.y * old.rect.height,
                       new.rect.minY + pointer.y * new.rect.height, accuracy: 0.000001)
    }

    func testZoomLimitsAndInvalidFactors() {
        XCTAssertEqual(Viewport.full.zoomed(by: 100).magnification, 32)
        XCTAssertEqual(Viewport.full.zoomed(by: 0.001), .full)
        for factor in [0, -1, Double.nan, .infinity] {
            XCTAssertEqual(Viewport.full.zoomed(by: factor), .full)
        }
        XCTAssertEqual(Viewport(rect: CGRect(x: Double.nan, y: 0, width: 1, height: 1)), .full)
    }

    func testSelectionsOutsideContentDoNotCorruptViewport() {
        XCTAssertEqual(Viewport.full.selecting(CGRect(x: 3, y: 3, width: 1, height: 1)), .full)
        XCTAssertEqual(Viewport.full.selecting(.zero), .full)
        XCTAssertEqual(Viewport.full.selecting(CGRect(x: -0.2, y: -0.2, width: 0.5, height: 0.5)).rect.width, 0.3, accuracy: 0.000001)
    }

    func testRepeatedInteractionsStayInsideSource() {
        var view = Viewport.full
        for index in 0..<1000 {
            view = view.zoomed(by: index.isMultiple(of: 3) ? 0.8 : 1.1)
                .panned(x: sin(Double(index)), y: cos(Double(index)))
            XCTAssertGreaterThanOrEqual(view.rect.minX, 0)
            XCTAssertGreaterThanOrEqual(view.rect.minY, 0)
            XCTAssertLessThanOrEqual(view.rect.maxX, 1.000001)
            XCTAssertLessThanOrEqual(view.rect.maxY, 1.000001)
        }
    }

    func testCaptureResolutionMatchesRetinaAndCapsMemory() {
        XCTAssertEqual(CaptureSizing.pixels(points: CGSize(width: 360, height: 200), scale: 2), CGSize(width: 720, height: 400))
        let large = CaptureSizing.pixels(points: CGSize(width: 5000, height: 3000), scale: 2)
        XCTAssertEqual(large.width, 4096)
        XCTAssertLessThanOrEqual(large.height, 4096)
        XCTAssertEqual(Int(large.height) % 2, 0)
    }
}
