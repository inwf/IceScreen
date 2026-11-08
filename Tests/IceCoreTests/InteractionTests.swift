import XCTest
@testable import IceCore
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class InteractionTests: XCTestCase {
    func testCommandShiftShortcutAndRegionRemainDistinct() throws {
        let key = Shortcut(keyCode: 34, command: true, function: false, shift: true, label: "I")
        XCTAssertEqual(key.display, "⇧⌘I")
        XCTAssertTrue(key.matches(keyCode: 34, command: true, option: false, control: false, function: false, shift: true))
        XCTAssertFalse(key.matches(keyCode: 34, command: true, option: false, control: false, function: false, shift: false))
        let region = try XCTUnwrap(key.regionVariant)
        XCTAssertEqual(region.display, "⌥⇧⌘I")
        XCTAssertFalse(region.matches(keyCode: 34, command: true, option: false, control: false, function: false, shift: true))
        XCTAssertTrue(region.matches(keyCode: 34, command: true, option: true, control: false, function: false, shift: true))
        XCTAssertEqual(try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(key)), key)
    }

    func testDefaultShortcutsAndLegacySettingsDecode() throws {
        XCTAssertEqual(Preferences().shortcut.display, "fn P")
        XCTAssertEqual(Preferences().effectiveRegionShortcut?.display, "⇧fn P")
        let data = Data(#"{"shortcut":{"keyCode":49,"command":false,"option":true,"control":true,"function":false,"label":"Space"},"defaultFPS":30,"multiWindow":true,"autoHide":true}"#.utf8)
        let settings = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertFalse(settings.shortcut.shift)
        XCTAssertEqual(settings.shortcut.display, "⌃⌥Space")
        XCTAssertEqual(settings.defaultFPS, 30)
        XCTAssertTrue(settings.multiWindow)
        XCTAssertTrue(settings.autoHide)
        XCTAssertTrue(settings.showHoverHints)
        XCTAssertNil(settings.regionShortcut)
    }

    func testCustomRegionShortcutOverridesAutomaticVariant() {
        var settings = Preferences()
        settings.regionShortcut = Shortcut(keyCode: 15, command: true, function: false, label: "R")
        XCTAssertEqual(settings.effectiveRegionShortcut?.display, "⌘R")
        settings.shortcut.shift = true
        XCTAssertEqual(settings.effectiveRegionShortcut?.display, "⌘R")
    }

    func testShortcutConflictsUsePhysicalKeysAndCheckDerivedRegion() {
        var settings = Preferences()
        var candidate = settings.shortcut
        candidate.label = "Different keyboard layout"
        XCTAssertNotNil(settings.shortcutConflict(candidate, for: .region))
        XCTAssertNotNil(settings.shortcutConflict(settings.effectiveRegionShortcut!, for: .closeAll))
        settings.closeAllShortcut = Shortcut(keyCode: 34, command: true, function: false, shift: true, label: "I")
        XCTAssertNotNil(settings.shortcutConflict(Shortcut(keyCode: 34, command: true, function: false, label: "I"), for: .capture))
        XCTAssertNil(settings.shortcutConflict(Shortcut(keyCode: 15, command: true, function: false, label: "R"), for: .capture))
    }

    func testTriggerModifierAndPreviewPersistWithLegacyDefaults() throws {
        var settings = Preferences()
        settings.triggerModifier = .option
        settings.quickLook = false
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.triggerModifier, .option)
        XCTAssertFalse(decoded.quickLook)
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.triggerModifier, .function)
        XCTAssertTrue(legacy.quickLook)
    }

    func testFunctionKeyUsedInShortcutDoesNotHidePanel() {
        var gesture = FunctionKeyGesture()
        XCTAssertFalse(gesture.flagsChanged(function: true, otherModifiers: false, at: 0))
        gesture.consume()
        XCTAssertFalse(gesture.flagsChanged(function: false, otherModifiers: false, at: 0.1))
        XCTAssertFalse(gesture.flagsChanged(function: true, otherModifiers: false, at: 1))
        XCTAssertTrue(gesture.flagsChanged(function: false, otherModifiers: false, at: 1.1))
    }

    func testOtherModifiersAndLongHoldDoNotCountAsTap() {
        var gesture = FunctionKeyGesture()
        XCTAssertFalse(gesture.flagsChanged(function: true, otherModifiers: false, at: 0))
        XCTAssertFalse(gesture.flagsChanged(function: true, otherModifiers: true, at: 0.1))
        XCTAssertFalse(gesture.flagsChanged(function: false, otherModifiers: false, at: 0.2))
        XCTAssertFalse(gesture.flagsChanged(function: true, otherModifiers: false, at: 1))
        XCTAssertFalse(gesture.flagsChanged(function: false, otherModifiers: false, at: 2))
    }

    func testDoubleTapDoesNotAlsoExecuteSingleTap() {
        var taps = ModifierTapSequence(interval: 0.3)
        XCTAssertFalse(taps.tap(at: 1))
        XCTAssertFalse(taps.takeSingle(at: 1.1))
        XCTAssertTrue(taps.tap(at: 1.2))
        XCTAssertFalse(taps.takeSingle(at: 2))
        XCTAssertFalse(taps.tap(at: 3))
        XCTAssertTrue(taps.takeSingle(at: 3.31))
        XCTAssertFalse(taps.takeSingle(at: 4))
    }

    func testCancellingTapWhenStartingShortcut() {
        var taps = ModifierTapSequence()
        XCTAssertFalse(taps.tap(at: 0))
        taps.reset()
        XCTAssertFalse(taps.takeSingle(at: 1))
    }

    func testDisablingAutoHideWhilePointerStillInsideRestoresCapture() {
        var state = PanelVisibility()
        state.updatePointer(inside: true, autoHide: true)
        XCTAssertTrue(state.automaticallyHidden)
        XCTAssertFalse(state.shouldCapture)
        state.updatePointer(inside: true, autoHide: false)
        XCTAssertFalse(state.automaticallyHidden)
        XCTAssertTrue(state.shouldCapture)
    }

    func testManualHideFromTransparentPanelCanBeRestored() {
        var state = PanelVisibility()
        state.updatePointer(inside: true, autoHide: true)
        state.toggleManual(at: 10)
        XCTAssertTrue(state.manuallyHidden)
        XCTAssertFalse(state.automaticallyHidden)
        XCTAssertFalse(state.isExpired(at: 69.9))
        XCTAssertTrue(state.isExpired(at: 70))
        state.toggleManual(at: 20)
        XCTAssertTrue(state.shouldCapture)
        XCTAssertNil(state.closeDeadline)
        XCTAssertFalse(state.isExpired(at: 100))
    }

    func testLeavingDoesNotResumeExplicitlyPausedCapture() {
        var state = PanelVisibility()
        state.paused = true
        state.updatePointer(inside: true, autoHide: true)
        state.updatePointer(inside: false, autoHide: true)
        XCTAssertFalse(state.shouldCapture)
        state.paused = false
        XCTAssertTrue(state.shouldCapture)
    }

    func testScreenWakeDoesNotOverrideSystemSleep() {
        var state = PanelVisibility()
        state.systemSleeping = true
        state.displaySleeping = true
        state.displaySleeping = false
        XCTAssertFalse(state.shouldCapture)
        state.systemSleeping = false
        XCTAssertTrue(state.shouldCapture)
    }

    func testDraggingAndMenusSuppressAutomaticHiding() {
        var state = PanelVisibility()
        state.interacting = true
        state.updatePointer(inside: true, autoHide: true)
        XCTAssertTrue(state.shouldCapture)
        state.interacting = false
        state.updatePointer(inside: true, autoHide: true)
        XCTAssertFalse(state.shouldCapture)
    }

    func testHoldingToggleKeysDoesNotCycleStateRepeatedly() {
        XCTAssertEqual(HoverAction.resolve(keyCode: 3, repeated: false), .frameRate)
        XCTAssertNil(HoverAction.resolve(keyCode: 3, repeated: true))
        XCTAssertNil(HoverAction.resolve(keyCode: 2, repeated: true))
        XCTAssertNil(HoverAction.resolve(keyCode: 51, repeated: true))
        XCTAssertEqual(HoverAction.resolve(keyCode: 24, repeated: true), .zoomIn)
    }

    func testTallRegionStaysOnDisplayWithoutToolbarOffset() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = PanelGeometry.fittedFrame(CGRect(x: -200, y: 800, width: 400, height: 200), aspectRatio: 0.1, visibleFrame: visible)
        XCTAssertTrue(visible.contains(frame))
        XCTAssertEqual(frame.width / frame.height, 0.1, accuracy: 0.000001)
        XCTAssertLessThanOrEqual(frame.height, 1080)
    }

    func testRegionZoomDoesNotChangeAspectRatioAtEitherLimit() {
        let original = Viewport(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.1))
        for factor in [0.0001, 0.5, 1.2, 10, 1000] {
            let zoomed = original.zoomed(by: factor)
            XCTAssertEqual(zoomed.rect.width / zoomed.rect.height, 6, accuracy: 0.000001)
            XCTAssertGreaterThanOrEqual(min(zoomed.rect.width, zoomed.rect.height), 1.0 / 32)
            XCTAssertLessThanOrEqual(max(zoomed.rect.width, zoomed.rect.height), 1)
        }
    }
}
