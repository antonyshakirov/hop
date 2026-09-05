import XCTest
@testable import HopCore

/// SPEC: docs/spec.md — "Which combination may be claimed".
final class HotkeyActivationTests: XCTestCase {

    func testEveryActionIsRegistrable() {
        let actions = HotkeyActivation.registrable()
        let expected = ModuleCatalog.modules.reduce(1) { $0 + $1.actions.count }

        XCTAssertEqual(actions.count, expected)
        XCTAssertTrue(actions.contains { $0.storageKey == "hotkey_timer" })
        XCTAssertTrue(actions.contains(ModuleCatalog.panelAction))
    }

    func testTheWindowZonesGoQuietTogether() {
        let off = HotkeyActivation.registrable(windowZones: false)
        XCTAssertFalse(off.contains { $0.isWindowZone })
        XCTAssertTrue(off.contains { $0.storageKey == "hotkey_timer" })

        let on = HotkeyActivation.registrable(windowZones: true)
        XCTAssertEqual(on.filter(\.isWindowZone).count, 18)
    }

    func testASwitchedOffModuleClaimsNothing() {
        let actions = HotkeyActivation.registrable(inactiveModules: ["timer", "color"])
        XCTAssertFalse(actions.contains { $0.storageKey == "hotkey_timer" })
        XCTAssertFalse(actions.contains { $0.storageKey == "hotkey_color" })
        XCTAssertTrue(actions.contains { $0.storageKey == "hotkey_ocr" }, "another module keeps its key")
    }

    func testThePanelKeepsItsKeyWhateverIsSwitchedOff() {
        let actions = HotkeyActivation.registrable(
            inactiveModules: Set(ModuleCatalog.allIDs))
        XCTAssertEqual(actions, [ModuleCatalog.panelAction])
    }

    func testTheZonesFollowTheirModule() {
        let moduleOff = HotkeyActivation.registrable(inactiveModules: ["windows"])
        XCTAssertFalse(moduleOff.contains { $0.isWindowZone })
        XCTAssertTrue(moduleOff.contains { $0.storageKey == "hotkey_timer" })
    }
}
