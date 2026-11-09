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

    func testSensitiveDetectionSeesSmallMovingIndicator() {
        let baseline = Array(repeating: UInt8(100), count: 1024)
        var changed = baseline
        changed[400] = 160
        var normal = IdleDetector()
        var sensitive = IdleDetector()
        sensitive.sensitive = true
        _ = normal.observe(baseline, at: 0)
        _ = sensitive.observe(baseline, at: 0)
        XCTAssertTrue(sensitive.isInitialSample)
        _ = normal.observe(changed, at: 1)
        _ = sensitive.observe(changed, at: 1)
        XCTAssertFalse(normal.didChange)
        XCTAssertTrue(sensitive.didChange)
        XCTAssertFalse(sensitive.isInitialSample)
    }

    func testDetectionReportsOneIdleEventAndQualifyingChange() {
        var detection = ContentDetection()
        XCTAssertNil(detection.tick(at: 100, idleAfter: 10))
        XCTAssertNil(detection.activity(at: 100, initial: true, changeAfter: 5))
        XCTAssertEqual(detection.tick(at: 110, idleAfter: 10), .idle)
        XCTAssertNil(detection.tick(at: 111, idleAfter: 10))
        XCTAssertEqual(detection.activity(at: 112, initial: false, changeAfter: 5), .change)
        XCTAssertFalse(detection.isIdle)
        XCTAssertNil(detection.activity(at: 113, initial: false, changeAfter: 5))
        XCTAssertNil(detection.tick(at: 122, idleAfter: 10))
        XCTAssertEqual(detection.tick(at: 123, idleAfter: 10), .idle)
    }

    func testCaptureResumeAndResolutionChangesEstablishNewBaseline() {
        var detection = ContentDetection()
        _ = detection.activity(at: 1, initial: true, changeAfter: 5)
        detection.reset()
        XCTAssertNil(detection.tick(at: 100, idleAfter: 10))
        XCTAssertNil(detection.activity(at: 100, initial: true, changeAfter: 5))
        XCTAssertNil(detection.activity(at: 200, initial: true, changeAfter: 5))
        XCTAssertNil(detection.tick(at: 209, idleAfter: 10))
        XCTAssertEqual(detection.tick(at: 210, idleAfter: 10), .idle)
    }
}
