import AppKit
import XCTest
@testable import Hop

@MainActor
final class SoundMenuBarIndicatorTests: XCTestCase {
    func testModuleMarkCanBeHiddenWithoutChangingAudioOrGlobalPreferences() {
        let name = "HopTests.SoundMenuBarIndicator"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(SoundMenuBarIndicator.isVisible(running: true, customized: true, moduleActive: true, defaults: defaults))
        defaults.set(false, forKey: "soundMenuBarMark")
        defaults.set(true, forKey: "soundMixerEnabled")
        XCTAssertFalse(SoundMenuBarIndicator.isVisible(running: true, customized: true, moduleActive: true, defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: "soundMixerEnabled"))
        XCTAssertNil(defaults.object(forKey: "menuBarIconOnly"))
        defaults.set(true, forKey: "soundMenuBarMark")
        XCTAssertTrue(SoundMenuBarIndicator.isVisible(running: true, customized: true, moduleActive: true, defaults: defaults))
    }

    func testUnmodifiedOrInactiveAudioDoesNotShowAMark() {
        XCTAssertFalse(SoundMenuBarIndicator.isVisible(running: false, customized: true, moduleActive: true))
        XCTAssertFalse(SoundMenuBarIndicator.isVisible(running: true, customized: false, moduleActive: true))
        XCTAssertFalse(SoundMenuBarIndicator.isVisible(running: true, customized: true, moduleActive: false))
    }

    func testAudioRingIsCenteredInItsLeftColumnAndDoesNotTouchDevMark() {
        XCTAssertEqual(MenuBarIcon.appAudioFrame.midY, MenuBarIcon.canvasSize.height / 2, accuracy: 0.01)
        XCTAssertEqual(MenuBarIcon.appAudioFrame.midX, 3, accuracy: 0.01)
        let ringStroke = MenuBarIcon.appAudioFrame.insetBy(dx: -0.475, dy: -0.475)
        let devStroke = MenuBarIcon.devMarkFrame.insetBy(dx: -0.55, dy: -0.55)
        XCTAssertFalse(ringStroke.intersects(devStroke), "Two touching marks look like one broken glyph")
    }
}
