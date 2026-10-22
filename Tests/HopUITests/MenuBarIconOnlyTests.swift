import AppKit
import XCTest
@testable import Hop

@MainActor
final class MenuBarIconOnlyTests: XCTestCase {
    func testIconOnlyClearsMarksAndClockAndRestoresCurrentState() throws {
        let defaults = UserDefaults.standard
        let keys = ["menuBarIconOnly", SettingsKey.showMenuBarCountdown,
                    "debugRedBadgeAlways", SettingsKey.vpnMenuBarMark]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.removeObject(forKey: "menuBarIconOnly")
        defaults.set(true, forKey: SettingsKey.showMenuBarCountdown)
        defaults.set(true, forKey: "debugRedBadgeAlways")
        defaults.set(true, forKey: SettingsKey.vpnMenuBarMark)
        let model = AppModel(preview: true)
        model.engine.onFinish = nil
        model.engine.start()
        defer { model.engine.reset() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let controller = StatusItemController(model: model, statusItem: item)
        controller.refreshButton()
        XCTAssertFalse(try XCTUnwrap(button.image).isTemplate)
        XCTAssertFalse(button.title.isEmpty)

        defaults.set(true, forKey: "menuBarIconOnly")
        controller.refreshButton()
        XCTAssertTrue(button.image === MenuBarIcon.dialTemplate)
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(model.engine.state, .running)
        XCTAssertTrue(defaults.bool(forKey: SettingsKey.showMenuBarCountdown))
        XCTAssertTrue(defaults.bool(forKey: SettingsKey.vpnMenuBarMark))

        model.engine.pause()
        defaults.set(false, forKey: "menuBarIconOnly")
        controller.refreshButton()
        XCTAssertFalse(try XCTUnwrap(button.image).isTemplate)
        XCTAssertFalse(button.title.isEmpty)
        XCTAssertEqual(model.engine.state, .paused)

        defaults.set(true, forKey: "menuBarIconOnly")
        model.engine.reset()
        model.engine.setDuration(0)
        model.engine.start()
        XCTAssertEqual(model.engine.state, .finished)
        controller.refreshButton()
        XCTAssertTrue(button.image === MenuBarIcon.dialTemplate)
        XCTAssertEqual(button.title, "")
        defaults.set(false, forKey: "menuBarIconOnly")
        controller.refreshButton()
        XCTAssertFalse(try XCTUnwrap(button.image).isTemplate)
    }
}
