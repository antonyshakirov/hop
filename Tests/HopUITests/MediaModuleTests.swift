import XCTest
import HopCore
@testable import Hop

@MainActor
final class MediaModuleTests: XCTestCase {
    func testExistingLayoutGainsAnIndependentOptInModuleOnlyOnce() throws {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.panelTabs, SettingsKey.moduleVisibilityMigrated,
                    SettingsKey.canonicalLayoutSeeded, SettingsKey.optInModulesSeeded170,
                    SettingsKey.mediaModuleSeeded, "moduleOrder"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let first = PanelTab(icon: "house", moduleKeys: ["convert"])
        let second = PanelTab(icon: "photo", moduleKeys: ["archive"])
        defaults.set(PanelTabsModel(tabs: [first, second]).encoded(), forKey: SettingsKey.panelTabs)
        defaults.set(true, forKey: SettingsKey.moduleVisibilityMigrated)
        defaults.set(true, forKey: SettingsKey.canonicalLayoutSeeded)
        defaults.set(true, forKey: SettingsKey.optInModulesSeeded170)
        defaults.removeObject(forKey: SettingsKey.mediaModuleSeeded)
        var tabs = PanelView.storedTabsModel()
        XCTAssertTrue(tabs.isHidden("media"))
        XCTAssertFalse(tabs.isHidden("convert"))
        XCTAssertEqual(tabs.tabs.map(\.id), [first.id, second.id])
        tabs.move(module: "media", toTab: second.id)
        tabs.setHidden("media", hidden: false)
        defaults.set(tabs.encoded(), forKey: SettingsKey.panelTabs)
        let reloaded = PanelView.storedTabsModel()
        XCTAssertFalse(reloaded.isHidden("media"))
        XCTAssertEqual(reloaded.tabID(containing: "media"), second.id)
        XCTAssertEqual(reloaded.tabID(containing: "convert"), first.id)
        XCTAssertEqual(reloaded.tabs.flatMap(\.moduleKeys).filter { $0 == "media" }.count, 1)
    }

    func testMediaHasItsOwnSettingsAndHandbookInEveryLanguage() {
        XCTAssertEqual(ModulePresentation.titleKey("media"), .mediaTitle)
        XCTAssertEqual(ModulePresentation.purposeKey("media"), .mediaPurpose)
        XCTAssertFalse(ModulePresentation.howKeys("media").isEmpty)
        for language in AppLanguage.allCases {
            for key in [L10nKey.mediaPurpose, .mediaOpen, .mediaOff] {
                XCTAssertFalse(L10n.t(key, language).isEmpty)
            }
        }
    }
}
