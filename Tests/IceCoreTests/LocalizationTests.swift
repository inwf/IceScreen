import XCTest
@testable import IceCore

final class LocalizationTests: XCTestCase {
    func testLanguageMigrationAndPersistencePreserveUserSettings() throws {
        let data = Data(#"{"autoHide":true,"autoHideOpacity":0.28,"panelOpacity":0.73,"appFrameRates":{"com.apple.Terminal":1},"detectionCommand":"echo 中文 English"}"#.utf8)
        let legacy = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(legacy.language, .chinese)
        for language in AppLanguage.allCases {
            var edited = legacy
            edited.language = language
            edited.normalize()
            let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(edited))
            XCTAssertEqual(restored, edited)
            XCTAssertEqual(restored.language, language)
            XCTAssertEqual(restored.autoHideOpacity, 0.28)
            XCTAssertEqual(restored.panelOpacity, 0.73)
            XCTAssertEqual(restored.fps(for: "com.apple.Terminal"), 1)
            XCTAssertEqual(restored.detectionCommand, "echo 中文 English")
        }
    }

    func testLocalizedMessagesFollowLanguageChangesAndPreserveUserText() throws {
        let previous = L10n.language
        defer { L10n.language = previous }
        let title = "项目 100% — %@ / English"
        L10n.language = .english
        XCTAssertEqual(L10n.text("来源：\(title)", "Source: \(title)"), "Source: \(title)")
        var preferences = Preferences()
        preferences.regionShortcut = preferences.shortcut
        XCTAssertEqual(preferences.shortcutConflict(preferences.shortcut, for: .capture),
                       "Window and region capture must use different shortcuts.")
        let response = try JSONDecoder().decode(MediaResponse.self,
            from: JSONEncoder().encode(MediaResponse(errorCode: .timeout)))
        XCTAssertEqual(response.errorCode?.localizedDescription, "The system media service did not respond.")
        L10n.language = .chinese
        XCTAssertEqual(L10n.text("来源：\(title)", "Source: \(title)"), "来源：\(title)")
        XCTAssertEqual(response.errorCode?.localizedDescription, "系统媒体服务没有响应。")
        XCTAssertEqual(preferences.shortcutConflict(preferences.shortcut, for: .capture),
                       "窗口捕获与区域捕获需要使用不同的快捷键。")
        XCTAssertEqual(L10n.text("中文", "English", language: .english), "English")
    }

    func testLegacyMediaMessagesStillDecode() throws {
        let response = try JSONDecoder().decode(MediaResponse.self, from: Data(#"{"error":"system error"}"#.utf8))
        XCTAssertNil(response.errorCode)
        XCTAssertEqual(response.error, "system error")
    }
}
