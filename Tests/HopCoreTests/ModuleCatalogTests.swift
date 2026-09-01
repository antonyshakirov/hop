import XCTest
@testable import HopCore

/// The module list used to live in four places at once — the panel's own
/// `allModules`, the hotkey actions, the help tabs and the settings sections —
/// and they had already drifted apart. These tests pin the single list down.
final class ModuleCatalogTests: XCTestCase {

    func testIdentifiersAreUniqueAndMatchThePanelDefaults() {
        let ids = ModuleCatalog.modules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 16)
        XCTAssertTrue(ids.contains("timer"))
        XCTAssertTrue(ids.contains("todos"))
        XCTAssertTrue(ids.contains("uninstall"))
    }

    func testEveryModuleHasExactlyOneOpenAction() {
        for module in ModuleCatalog.modules {
            let opens = module.actions.filter { $0.id == "open" }
            XCTAssertEqual(opens.count, 1, "module \(module.id)")
        }
    }

    func testOnlyLegacyActionsCarryADefaultCombo() {
        let withDefaults = ModuleCatalog.modules
            .flatMap(\.actions)
            .filter { $0.defaultCombo != nil }
            .map(\.storageKey)
        XCTAssertEqual(
            Set(withDefaults),
            ["hotkey_timer", "hotkey_awake", "hotkey_color", "hotkey_ocr", "hotkey_keyboardLock"]
        )
        XCTAssertNotNil(ModuleCatalog.panelAction.defaultCombo)
    }

    func testHotKeyIdentifiersAreUnique() {
        var ids = ModuleCatalog.modules.flatMap(\.actions).map(\.hotKeyID)
        ids.append(ModuleCatalog.panelAction.hotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testStorageKeysOfTheLegacySixAreUnchanged() {
        XCTAssertEqual(ModuleCatalog.panelAction.storageKey, "hotkey_panel")
        XCTAssertEqual(ModuleCatalog.module("timer")?.actions.first?.storageKey, "hotkey_timer")
        XCTAssertEqual(ModuleCatalog.module("awake")?.actions.first?.storageKey, "hotkey_awake")
        XCTAssertEqual(ModuleCatalog.module("color")?.actions.first?.storageKey, "hotkey_color")
        XCTAssertEqual(ModuleCatalog.module("ocr")?.actions.first?.storageKey, "hotkey_ocr")
        XCTAssertEqual(ModuleCatalog.module("keyboard")?.actions.first?.storageKey, "hotkey_keyboardLock")
    }

    func testModulesThatShipHiddenAreTheOptInOnes() {
        let hidden = ModuleCatalog.modules.filter(\.hiddenOnFirstRun).map(\.id)
        XCTAssertEqual(Set(hidden), ["color", "ocr", "vpn"])
    }

    func testStorageKeysAreUniqueSoTwoActionsCannotShareASavedCombo() {
        var keys = ModuleCatalog.modules.flatMap(\.actions).map(\.storageKey)
        keys.append(ModuleCatalog.panelAction.storageKey)
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testAnActionIsItsOwnIdentityInASet() throws {
        let all = ModuleCatalog.modules.flatMap(\.actions)
        let actions = Set(all)
        XCTAssertEqual(actions.count, all.count)
        XCTAssertTrue(actions.contains(try XCTUnwrap(ModuleCatalog.open("timer"))))
        XCTAssertFalse(actions.contains(ModuleCatalog.panelAction))
    }

    func testTheOpenActionIsReachableByModuleIdentifier() {
        XCTAssertEqual(ModuleCatalog.open("timer"), ModuleCatalog.module("timer")?.openAction)
        XCTAssertEqual(ModuleCatalog.open("timer")?.storageKey, "hotkey_timer")
        XCTAssertNil(ModuleCatalog.open("nothing-of-the-sort"))
    }
}
