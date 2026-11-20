import XCTest
import IceCore

final class MediaButtonLayoutTests: XCTestCase {
    func testSizesAndLimits() throws {
        for (w, h, play, track) in [(240,150,30,30), (360,200,38,32), (640,360,46,38),
                                     (1200,720,46,38), (1200,120,30,30), (240,720,30,30)] {
            let layout = try XCTUnwrap(MediaButtonLayout(size: CGSize(width: w, height: h), seekable: true))
            XCTAssertEqual(layout.play.width, CGFloat(play))
            XCTAssertEqual(layout.previous?.width, CGFloat(track))
            XCTAssertEqual(layout.next?.width, CGFloat(track))
        }
        let midway = try XCTUnwrap(MediaButtonLayout(size: CGSize(width: 300, height: 175), seekable: false))
        XCTAssertEqual(midway.play.width, 34)
        XCTAssertNil(midway.seek)
    }

    func testTargetsRespectThresholdsAndKeepDragSpace() throws {
        XCTAssertNil(MediaButtonLayout(size: CGSize(width: 149, height: 300), seekable: true))
        XCTAssertNil(MediaButtonLayout(size: CGSize(width: 400, height: 99), seekable: true))
        for w in [150, 229, 230, 240, 360, 640, 1000] {
            for h in [100, 144, 145, 200, 360] {
                for seekable in [false, true] {
                    let size = CGSize(width: w, height: h)
                    let row = try XCTUnwrap(MediaButtonLayout(size: size, seekable: seekable))
                    XCTAssertEqual(row.play.midX, size.width / 2)
                    XCTAssertEqual(row.seek != nil, seekable && w >= 230 && h >= 145)
                    XCTAssertEqual(row.previous != nil, w >= 230)
                    XCTAssertEqual(row.next != nil, w >= 230)
                    let handle = CGRect(x: size.width - 38, y: size.height - 38, width: 30, height: 30)
                    for button in [row.play, row.previous, row.next].compactMap({ $0 }) {
                        XCTAssertGreaterThan(button.minY, 38)
                        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(button))
                        XCTAssertFalse(button.intersects(handle))
                        if let seek = row.seek { XCTAssertLessThan(button.maxY, seek.minY) }
                    }
                    if let left = row.previous, let right = row.next {
                        XCTAssertLessThan(left.maxX, row.play.minX)
                        XCTAssertLessThan(row.play.maxX, right.minX)
                        XCTAssertEqual(left.midY, row.play.midY, accuracy: 0.0001)
                    }
                }
            }
        }
    }
}
