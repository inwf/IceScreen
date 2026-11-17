import XCTest
@testable import IceCore

final class PanelMessageLayoutTests: XCTestCase {
    func testMessagesStayCenteredAcrossPanelSizesAndOrigins() {
        for origin in [CGPoint.zero, CGPoint(x: -1920, y: -240), CGPoint(x: 1200, y: 900)] {
            for size in [CGSize(width: 80, height: 40), CGSize(width: 180, height: 140), CGSize(width: 640, height: 360)] {
                let bounds = CGRect(origin: origin, size: size).insetBy(dx: 8, dy: 8)
                for messageSize in [CGSize(width: 120, height: 32), CGSize(width: 350, height: 64), CGSize(width: 700, height: 300)] {
                    let layout = PanelMessageLayout(in: bounds, messageSize: messageSize)
                    XCTAssertEqual(layout.message.midX, bounds.midX, accuracy: 0.001)
                    XCTAssertEqual(layout.message.midY, bounds.midY, accuracy: 0.001)
                    XCTAssertTrue(bounds.contains(layout.message))
                    XCTAssertNil(layout.action)
                }
            }
        }
    }

    func testStatusAndActionRemainCenteredWithoutOverlap() {
        for height in [60.0, 100, 220] {
            let bounds = CGRect(x: 8, y: 40, width: 164, height: height)
            let layout = PanelMessageLayout(in: bounds, messageSize: CGSize(width: 380, height: 180),
                                            actionSize: CGSize(width: 124, height: 30))
            let action = try! XCTUnwrap(layout.action)
            XCTAssertEqual(action.size, CGSize(width: 124, height: 30))
            XCTAssertEqual(layout.message.midX, bounds.midX)
            XCTAssertEqual(action.midX, bounds.midX)
            XCTAssertEqual(layout.message.union(action).midY, bounds.midY)
            XCTAssertEqual(action.minY - layout.message.maxY, 8)
            XCTAssertTrue(bounds.contains(layout.message))
            XCTAssertTrue(bounds.contains(action))
            XCTAssertFalse(layout.message.intersects(action))
        }
    }

    func testInsufficientSpaceNeverProducesNegativeDimensions() {
        for size in [CGSize.zero, CGSize(width: 8, height: 4), CGSize(width: 50, height: 30)] {
            let layout = PanelMessageLayout(in: CGRect(origin: .zero, size: size),
                messageSize: CGSize(width: 300, height: 100), actionSize: CGSize(width: 124, height: 30))
            XCTAssertGreaterThanOrEqual(layout.message.width, 0)
            XCTAssertGreaterThanOrEqual(layout.message.height, 0)
            XCTAssertLessThanOrEqual(layout.message.maxY, size.height)
            XCTAssertLessThanOrEqual(layout.action!.maxY, size.height)
        }
    }
}
