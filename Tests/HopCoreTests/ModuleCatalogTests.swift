import XCTest
@testable import HopCore

/// The module list used to live in four places at once — the panel's own
/// `allModules`, the hotkey actions, the help tabs and the settings sections —
/// and they had already drifted apart. These tests pin the single list down.
final class ModuleCatalogTests: XCTestCase {

    func testIdentifiersAreUniqueAndMatchThePanelDefaults() {
        let ids = ModuleCatalog.modules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 18)
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
            ["timer", "awake", "color", "ocr", "keyboard", "convert", "archive", "uninstall", "windows",
             "shot", "annotate"]
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

    /// Every other action ships without a combination and claims nothing on
    /// anybody's behalf.
    func testOnlyTheOpeningActionsCarryADefaultCombo() {
        let withDefaults = ModuleCatalog.modules
            .flatMap(\.actions)
            .filter { $0.defaultCombo != nil && !$0.isWindowZone }
            .map(\.storageKey)
        XCTAssertEqual(
            Set(withDefaults),
            ["hotkey_timer", "hotkey_awake", "hotkey_color", "hotkey_ocr", "hotkey_keyboardLock",
             "hotkey_shot", "hotkey_annotate"]
        )
        XCTAssertNotNil(ModuleCatalog.panelAction.defaultCombo)
    }

    /// Two actions shipping the SAME combination is a defect the user meets as
    /// "shortcut is taken" on a fresh install, with one of the two silently dead:
    /// the timer and the zone for the right two thirds once shipped the same
    /// ⌃⌥T. The zones follow Rectangle's map, so a clash is settled by moving
    /// the module.
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

    /// Onboarding walks these groups. A module missing from them would never be
    /// offered on a fresh install, and one listed twice would be asked about
    /// twice.
    func testTheOnboardingGroupsCoverEveryModuleExactlyOnce() {
        let listed = ModuleCatalog.onboardingGroups.flatMap { $0 }
        XCTAssertEqual(Set(listed).count, listed.count, "a module is listed twice")
        // "apps" is not a module until a grid exists; everything else is.
        XCTAssertEqual(Set(listed).subtracting(["apps"]), Set(ModuleCatalog.allIDs))
        XCTAssertTrue(listed.contains("apps"))
        XCTAssertTrue(ModuleCatalog.onboardingGroups.allSatisfy { !$0.isEmpty })
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

    /// A guide letter is an address printed on the site.
    func testTheMarkupModulesCarryTheirOwnGuideLetters() {
        XCTAssertEqual(ModuleCatalog.module("shot")?.guideLetter, "g")
        XCTAssertEqual(ModuleCatalog.module("annotate")?.guideLetter, "i")

        let letters = ModuleCatalog.modules.map(\.guideLetter)
        XCTAssertEqual(Set(letters).count, letters.count, "a guide letter is used twice")
    }

    func testEveryHotkeyIdentifierIsUsedOnce() {
        let ids = ModuleCatalog.allActions.map(\.hotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count, "two actions claim one hotkey id")
    }

    func testTheShotModuleOffersFourWaysToCapture() {
        XCTAssertEqual(ModuleCatalog.module("shot")?.actions.map(\.id).sorted(),
                       ["open", "repeat", "screen", "window"])
    }

    /// The rest stay free so they collide with nothing.
    func testOnlyTheTwoOpenActionsClaimACombination() {
        let claimed = ["shot", "annotate"].compactMap { ModuleCatalog.module($0) }
            .flatMap(\.actions).filter { $0.defaultCombo != nil }.map(\.id)
        XCTAssertEqual(claimed.sorted(), ["open", "open"])
    }

    /// A combination spoken for twice is dead on a clean install.
    func testTheNewCombinationsAreFreeOfTheOnesAlreadyThere() {
        let combos = ModuleCatalog.allActions.compactMap(\.defaultCombo)
        XCTAssertEqual(Set(combos).count, combos.count, "two actions claim one combination")
    }

    /// A function names its own key: screenshot on S, draw on screen on D.
    /// SPEC: docs/spec.md — hotkeys.
    func testEveryDefaultIsTheFirstLetterOfWhatItDoes() {
        let wanted: [String: UInt32] = [
            "hotkey_panel": 4,          // Hop
            "hotkey_shot": 1,           // screenshot
            "hotkey_annotate": 2,       // draw on screen
            "hotkey_timer": 17,         // timer
            "hotkey_awake": 0,          // awake
            "hotkey_color": 8,          // colour picker
            "hotkey_keyboardLock": 40,  // keyboard lock
            "hotkey_ocr": 15,           // text Recognition: T is the timer's
        ]
        for (key, code) in wanted {
            let action = ModuleCatalog.allActions.first { $0.storageKey == key }
            XCTAssertEqual(action?.defaultCombo?.keyCode, code, "\(key) lost its letter")
            XCTAssertEqual(action?.defaultCombo?.modifiers,
                           ModuleCombo.control | ModuleCombo.option, "\(key) changed modifiers")
        }
    }

    func testBothMarkupModulesOwnSettings() {
        XCTAssertTrue(ModuleCatalog.hasSettings("shot"))
        XCTAssertTrue(ModuleCatalog.hasSettings("annotate"))
    }

    /// A module left out of the groups is one nobody learns exists.
    func testTheWizardShowsEveryModule() {
        let shown = Set(ModuleCatalog.onboardingGroups.flatMap { $0 })
        for module in ModuleCatalog.modules {
            XCTAssertTrue(shown.contains(module.id), "\(module.id) is in no onboarding group")
        }
    }
}
