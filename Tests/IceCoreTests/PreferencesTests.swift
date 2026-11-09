import XCTest
@testable import IceCore

final class PreferencesTests: XCTestCase {
    func testPreferencesPreserveApplicationSettings() throws {
        var settings = Preferences()
        settings.appFrameRates["com.apple.Terminal"] = 1
        settings.preferredWidth = 480
        settings.multiWindow = false
        settings.shortcut = Shortcut(keyCode: 35, option: false, control: false, function: true, label: "P")
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
        XCTAssertEqual(restored.fps(for: "com.apple.Terminal"), 1)
        XCTAssertEqual(restored.fps(for: "org.example.Video"), 10)
        XCTAssertEqual(restored.shortcut.display, "fn P")
    }

    func testNormalizationBoundsConfiguration() {
        var settings = Preferences()
        settings.defaultFPS = 500
        settings.appFrameRates = ["valid": 60, "invalid": -1]
        settings.idleSeconds = .infinity
        settings.preferredWidth = -200
        settings.normalize()
        XCTAssertEqual(settings.defaultFPS, 10)
        XCTAssertEqual(settings.appFrameRates, ["valid": 60])
        XCTAssertEqual(settings.idleSeconds, 20)
        XCTAssertEqual(settings.preferredWidth, 160)
    }

    func testDetectionAndAppearanceSettingsMigrateAndPersist() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.changeDetection)
        XCTAssertTrue(legacy.dimOnHover)
        XCTAssertTrue(legacy.showMenuBarIcon)
        var preferences = legacy
        preferences.changeDetection = true
        preferences.sensitiveDetection = true
        preferences.detectionNotifications = false
        preferences.detectionCommand = "echo \"$ICESCREEN_EVENT\""
        preferences.detectionCommandTimeout = 30
        preferences.showMenuBarIcon = false
        preferences.hoverBlur = 0.7
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)), preferences)
        preferences.changeSeconds = -10
        preferences.detectionCommandTimeout = .infinity
        preferences.hoverBlur = 20
        preferences.normalize()
        XCTAssertEqual(preferences.changeSeconds, 1)
        XCTAssertEqual(preferences.detectionCommandTimeout, 15)
        XCTAssertEqual(preferences.hoverBlur, 1)
    }
}
