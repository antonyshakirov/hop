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

    /// A key is only worth having where pressing it shows something without the
    /// panel: a window of its own, or a change on screen. The other modules are
    /// read IN the panel, which already has a key of its own. The window manager
    /// is the exception with no "open" at all — its eighteen zones ARE its keys.
    func testOnlyModulesAKeyCanShowCarryAnAction() {
        let withActions = ModuleCatalog.modules.filter { !$0.actions.isEmpty }.map(\.id)
        XCTAssertEqual(
            Set(withActions),
            ["timer", "awake", "color", "ocr", "keyboard", "convert", "archive", "uninstall", "windows"]
        )
        for module in ModuleCatalog.modules where !module.actions.isEmpty && module.id != "windows" {
            XCTAssertEqual(module.actions.filter { $0.id == "open" }.count, 1, "module \(module.id)")
        }
        XCTAssertNil(ModuleCatalog.open("windows"))
    }

    func testEveryWindowZoneIsItsOwnRebindableAction() {
        let zones = ModuleCatalog.zoneActions
        XCTAssertEqual(zones.count, 18)
        XCTAssertTrue(zones.allSatisfy(\.isWindowZone))
        XCTAssertTrue(zones.allSatisfy { $0.defaultCombo != nil }, "a zone ships with a key")
        XCTAssertEqual(ModuleCatalog.module("windows")?.actions, zones)
        XCTAssertEqual(zones.first?.zoneName, "leftHalf")
        XCTAssertEqual(zones.first?.storageKey, "hotkey_zone_leftHalf")
        XCTAssertNil(ModuleCatalog.panelAction.zoneName)
    }

    /// Only the actions that had a combination before the catalog keep one; the
    /// three window actions added with it claim nothing on anybody's behalf.
    func testOnlyLegacyActionsCarryADefaultCombo() {
        let withDefaults = ModuleCatalog.modules
            .flatMap(\.actions)
            .filter { $0.defaultCombo != nil && !$0.isWindowZone }
            .map(\.storageKey)
        XCTAssertEqual(
            Set(withDefaults),
            ["hotkey_timer", "hotkey_awake", "hotkey_color", "hotkey_ocr", "hotkey_keyboardLock"]
        )
        XCTAssertNotNil(ModuleCatalog.panelAction.defaultCombo)
    }

    /// Two actions shipping the SAME combination is a defect the user meets as
    /// "shortcut is taken" on a fresh install, with one of the two silently dead:
    /// the timer and the zone for the right two thirds both shipped ⌃⌥T until
    /// 2026-09-02. The zones follow Rectangle's map, so a clash is settled by
    /// moving the module.
    func testNoTwoActionsShipTheSameCombination() {
        let combos = (ModuleCatalog.allActions).compactMap(\.defaultCombo)
        var seen: [ModuleCombo: String] = [:]
        for action in ModuleCatalog.allActions {
            guard let combo = action.defaultCombo else { continue }
            XCTAssertNil(seen[combo], "\(action.id) ships the combination of \(seen[combo] ?? "")")
            seen[combo] = action.id
        }
        XCTAssertEqual(Set(combos).count, combos.count)
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
        let all = ModuleCatalog.modules.flatMap(\.actions)  // 8 open actions
        let actions = Set(all)
        XCTAssertEqual(actions.count, all.count)
        XCTAssertTrue(actions.contains(try XCTUnwrap(ModuleCatalog.open("timer"))))
        XCTAssertFalse(actions.contains(ModuleCatalog.panelAction))
    }

    /// The letters are a contract with the website: reassigning one would make
    /// old links show a different module than the person picked.
    /// SPEC: hop-website/docs/guide-code.md
    func testGuideLettersMatchThePublishedTable() {
        let letters = Dictionary(uniqueKeysWithValues: ModuleCatalog.modules.map { ($0.id, $0.guideLetter) })
        XCTAssertEqual(letters["timer"], "t")
        XCTAssertEqual(letters["tracker"], "r")
        XCTAssertEqual(letters["awake"], "a")
        XCTAssertEqual(letters["system"], "m")
        XCTAssertEqual(letters["clipboard"], "c")
        XCTAssertEqual(letters["convert"], "f")
        XCTAssertEqual(letters["windows"], "w")
        XCTAssertEqual(letters["archive"], "z")
        XCTAssertEqual(letters["ocr"], "o")
        XCTAssertEqual(letters["keyboard"], "k")
        XCTAssertEqual(letters["speedtest"], "s")
        XCTAssertEqual(letters["vpn"], "n")
        XCTAssertEqual(letters["uninstall"], "u")
        XCTAssertEqual(letters["torrent"], "d")
        XCTAssertEqual(letters["color"], "p")
        XCTAssertEqual(letters["todos"], "l", "free letter; the site skips one it does not know")
        XCTAssertEqual(Set(letters.values).count, letters.count)
    }

    func testGuideCodeCarriesOnlyWhatTheUserStillSees() {
        XCTAssertEqual(ModuleCatalog.guideCode(shown: ["timer", "clipboard", "convert"]), "tcf")
        XCTAssertEqual(ModuleCatalog.guideCode(shown: []), "")
        XCTAssertEqual(ModuleCatalog.guideCode(shown: ["nothing-of-the-sort"]), "")
    }

    func testTheOpenActionIsReachableByModuleIdentifier() {
        XCTAssertEqual(ModuleCatalog.open("timer"), ModuleCatalog.module("timer")?.openAction)
        XCTAssertEqual(ModuleCatalog.open("timer")?.storageKey, "hotkey_timer")
        XCTAssertNil(ModuleCatalog.open("nothing-of-the-sort"))
        XCTAssertNil(ModuleCatalog.open("clipboard"), "read in the panel, not by a key")
    }

    /// The module page reads this to decide whether a rule belongs under the
    /// on/off switch. A name that no module answers to would draw the rule over
    /// nothing — the very thing the list exists to prevent.
    func testEveryModuleWithSettingsIsAModuleThatExists() {
        let ids = Set(ModuleCatalog.allIDs)
        for id in ModuleCatalog.modulesWithSettings {
            XCTAssertTrue(ids.contains(id), "no module answers to \(id)")
        }
        XCTAssertTrue(ModuleCatalog.hasSettings("timer"))
        for bare in ["speedtest", "ocr", "keyboard", "uninstall"] {
            XCTAssertFalse(ModuleCatalog.hasSettings(bare), "\(bare) carries the switch alone")
        }
        XCTAssertFalse(ModuleCatalog.hasSettings("nothing-of-the-sort"))
    }
}
