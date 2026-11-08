import XCTest
@testable import IceCore

final class IdleDetectorTests: XCTestCase {
    func testStopsChangingThenResumes() {
        var detector = IdleDetector(threshold: 20)
        XCTAssertFalse(detector.observe([30, 60, 90], at: 100))
        XCTAssertFalse(detector.observe([30, 60, 90], at: 119))
        XCTAssertTrue(detector.observe([30, 60, 90], at: 120))
        XCTAssertFalse(detector.observe([60, 90, 120], at: 121))
        XCTAssertFalse(detector.isIdle(at: 140))
        XCTAssertTrue(detector.isIdle(at: 141))
    }

    func testIdleWhenScreenCaptureStopsProducingIdenticalFrames() {
        var detector = IdleDetector(threshold: 10)
        XCTAssertFalse(detector.observe([100, 100], at: 5))
        XCTAssertTrue(detector.isIdle(at: 15))
        detector.reset()
        XCTAssertFalse(detector.isIdle(at: 100))
    }

    func testSmallNoiseIgnoredButAccumulatedDriftIsDetected() {
        var detector = IdleDetector(threshold: 5, tolerance: 2)
        XCTAssertFalse(detector.observe([100, 100], at: 0))
        XCTAssertTrue(detector.observe([101, 102], at: 5))
        XCTAssertFalse(detector.observe([104, 105], at: 6))
    }

    func testResolutionChangeRestartsObservation() {
        var detector = IdleDetector(threshold: 5)
        XCTAssertFalse(detector.observe([50], at: 0))
        XCTAssertFalse(detector.observe([50, 50], at: 20))
        XCTAssertFalse(detector.observe([], at: 30))
    }
}
