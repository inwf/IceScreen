import XCTest
@testable import IceCore

final class SmartCaptureTests: XCTestCase {
    func testSemanticBoundaryWinsOverNestedVideoRectangles() {
        let outer = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
        let result = SmartCapture.select(at: CGPoint(x: 0.5, y: 0.5), candidates: [
            .init(rect: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)),
            .init(rect: outer, semantic: true),
            .init(rect: CGRect(x: 0, y: 0, width: 1, height: 1), semantic: true)
        ])
        XCTAssertEqual(result.rect, outer)
    }
    func testOnlyBoundaryUnderPointerIsChosen() {
        let result = SmartCapture.select(at: CGPoint(x: 0.95, y: 0.05), candidates: [
            .init(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)),
            .init(rect: CGRect(x: 0, y: 0, width: 0.99, height: 0.99))
        ])
        XCTAssertEqual(result.rect, CGRect(x: 0.75, y: 0, width: 0.25, height: 0.25))
    }
    func testVisionCoordinatesFlipVertically() {
        let result = SmartCapture.fromVision(CGRect(x: 0.1, y: 0.1, width: 0.6, height: 0.2))
        XCTAssertEqual(result.minY, 0.7, accuracy: 0.00001)
        XCTAssertEqual(result.width, 0.6)
    }
}
