import XCTest
@testable import HopCore

/// Hiding a module used to be the only way to stop it claiming a global
/// combination, and the rule lived inside the hotkey manager where nothing
/// could test it.
final class HotkeyActivationTests: XCTestCase {

    func testHiddenModuleReleasesItsCombo() {
        let actions = HotkeyActivation.registrable(hidden: ["timer"], hiddenKeepHotkeys: false)

        XCTAssertFalse(actions.contains { $0.storageKey == "hotkey_timer" })
        XCTAssertTrue(actions.contains { $0.storageKey == "hotkey_awake" })
    }

    func testTheSwitchGivesHiddenModulesTheirCombosBack() {
        let actions = HotkeyActivation.registrable(hidden: ["timer"], hiddenKeepHotkeys: true)

        XCTAssertTrue(actions.contains { $0.storageKey == "hotkey_timer" })
    }

    func testTheWindowZonesGoQuietTogether() {
        let off = HotkeyActivation.registrable(hidden: [], hiddenKeepHotkeys: false, windowZones: false)
        XCTAssertFalse(off.contains { $0.isWindowZone })
        XCTAssertTrue(off.contains { $0.storageKey == "hotkey_timer" })

        let on = HotkeyActivation.registrable(hidden: [], hiddenKeepHotkeys: false, windowZones: true)
        XCTAssertEqual(on.filter(\.isWindowZone).count, 18)
    }

    func testAHiddenWindowManagerTakesItsZonesWithIt() {
        let actions = HotkeyActivation.registrable(hidden: ["windows"], hiddenKeepHotkeys: false)
        XCTAssertFalse(actions.contains { $0.isWindowZone })
    }

    func testThePanelActionIsAlwaysThere() {
        let actions = HotkeyActivation.registrable(
            hidden: Set(ModuleCatalog.allIDs), hiddenKeepHotkeys: false)

        XCTAssertEqual(actions.map(\.storageKey), ["hotkey_panel"])
    }

    func testNothingHiddenMeansEveryAction() {
        let actions = HotkeyActivation.registrable(hidden: [], hiddenKeepHotkeys: false)
        let expected = ModuleCatalog.modules.reduce(1) { $0 + $1.actions.count }

        XCTAssertEqual(actions.count, expected)
    }
}
