import XCTest
@testable import IceCore

final class RequestTests: XCTestCase {
    func testCompleteRequestRoundTripsThroughIPC() throws {
        let request = try CaptureRequest.parse(["--app", "Terminal", "--window", "Build", "--zoom", "bottom-left:5x", "--region"])
        XCTAssertEqual(request.app, "Terminal")
        XCTAssertEqual(request.window, "Build")
        XCTAssertEqual(request.anchor, .bottomLeft)
        XCTAssertEqual(request.zoom, 5)
        XCTAssertTrue(request.region)
        XCTAssertEqual(try JSONDecoder().decode(CaptureRequest.self, from: JSONEncoder().encode(request)), request)
    }

    func testAllZoomPositionsAndBareFactors() throws {
        for anchor in ZoomAnchor.allCases {
            XCTAssertEqual(try CaptureRequest.parse(["--zoom", "\(anchor.rawValue):2"]).anchor, anchor)
        }
    }

    func testRejectsInvalidOrMissingArguments() {
        for args in [["--app"], ["--unknown"], ["--window", "--app"], ["--app", ""],
                     ["--zoom", "middle:2x"], ["--zoom", "center:0x"], ["--zoom", "center:33x"],
                     ["--zoom", "center:nan"], ["--zoom", "center:inf"], ["--zoom", "2x"],
                     ["--zoom", "center:2xx"], ["--zoom", "center::2x"]] {
            XCTAssertThrowsError(try CaptureRequest.parse(args), "Accepted invalid arguments: \(args)")
        }
    }

    func testWindowIdentityAndAppDisambiguation() throws {
        let id = try CaptureRequest.parse(["--app", "com.apple.Terminal", "--window", "42"])
        XCTAssertTrue(id.matches(appName: "Terminal", bundleID: "com.apple.Terminal", title: "build", windowID: 42))
        XCTAssertFalse(id.matches(appName: "Terminal", bundleID: "com.apple.Terminal", title: "42", windowID: 43))
        let title = try CaptureRequest.parse(["--app", "term", "--window", "BUILD"])
        XCTAssertTrue(title.matches(appName: "Terminal", bundleID: "com.apple.Terminal", title: "daily build", windowID: 99))
        XCTAssertFalse(title.matches(appName: "Editor", bundleID: "org.example.Editor", title: "daily build", windowID: 99))
    }
}
