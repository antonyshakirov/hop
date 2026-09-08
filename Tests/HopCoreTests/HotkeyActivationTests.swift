import XCTest
@testable import HopCore

/// SPEC: docs/spec.md — "Which combination may be claimed".
final class HotkeyActivationTests: XCTestCase {

    func testEveryActionIsRegistrable() {
        let actions = HotkeyActivation.registrable(drawingLayerUp: true)
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

    /// SPEC: docs/spec.md — "Draw over the screen": the mode key belongs to a
    /// layer that is on screen, and holds nothing away from other apps until it is.
    func testTheDrawingModeKeyIsClaimedOnlyWhileTheLayerIsUp() {
        let down = HotkeyActivation.registrable()
        XCTAssertFalse(down.contains(ModuleCatalog.annotatePassAction))
        XCTAssertTrue(down.contains { $0.storageKey == "hotkey_annotate" },
                      "the layer is still opened by its own key")

        let up = HotkeyActivation.registrable(drawingLayerUp: true)
        XCTAssertTrue(up.contains(ModuleCatalog.annotatePassAction))
    }

    func testTheModeKeyGoesWithItsModule() {
        let off = HotkeyActivation.registrable(inactiveModules: ["annotate"], drawingLayerUp: true)
        XCTAssertFalse(off.contains(ModuleCatalog.annotatePassAction))
    }

    func testThePanelKeepsItsKeyWhateverIsSwitchedOff() {
        let actions = HotkeyActivation.registrable(
            inactiveModules: Set(ModuleCatalog.allIDs), drawingLayerUp: true)
        XCTAssertEqual(actions, [ModuleCatalog.panelAction])
    }

    func testTheZonesFollowTheirModule() {
        let moduleOff = HotkeyActivation.registrable(inactiveModules: ["windows"])
        XCTAssertFalse(moduleOff.contains { $0.isWindowZone })
        XCTAssertTrue(moduleOff.contains { $0.storageKey == "hotkey_timer" })
    }
}
