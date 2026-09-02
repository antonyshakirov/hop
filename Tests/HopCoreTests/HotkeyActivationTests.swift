import XCTest
@testable import HopCore

/// Hiding a module used to take its combination away, and a setting existed to
/// undo that. Both are gone: a key answers whether or not the module is drawn in
/// the panel (Anton, 2026-09-02). The window zones keep their own switch.
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
}
