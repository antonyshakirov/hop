import XCTest
import HopCore
@testable import Hop

@MainActor
final class HotfixReleaseTests: XCTestCase {
    func testCoolingAndClipboardReleaseKeepsItsOwnCardAndLocalizedNotes() {
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.5"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.5.0 – 2026-11-16"), lang.rawValue)
            for key in [L10nKey.news25Cooling, .news25Lid, .news25Clipboard] {
                XCTAssertTrue(notes.contains("• " + L10n.t(key, lang)), lang.rawValue)
            }
        }
    }
    func testHardwarePermissionPatchHasLocalizedNotesWithoutANewPanelCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.5.1"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.5.1 – 2026-11-16\n\n• "), lang.rawValue)
            let current = notes.components(separatedBy: "2.5.1 – ")[1].components(separatedBy: "2.5.0 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 1, lang.rawValue)
        }
    }

    func testResponsivenessPatchHasThreeLocalizedNotesWithoutANewPanelCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.5.2"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.5.2 – 2026-11-16\n\n• "), lang.rawValue)
            let current = notes.components(separatedBy: "2.5.2 – ")[1].components(separatedBy: "2.5.1 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 3, lang.rawValue)
        }
    }

    func testDevelopmentPreviewResetsOnlyTheCurrentReleaseCard() throws {
        let suite = "release-preview-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "newsSeen.2.5.3")
        defaults.set(4, forKey: "newsShown.2.5.3")
        defaults.set(Date(timeIntervalSince1970: 1), forKey: "newsFirstShown.2.5.3")
        defaults.set(true, forKey: "newsSeen.2.5")
        defaults.set(true, forKey: "newsSeen.2.4.5")
        defaults.set("de", forKey: SettingsKey.appLanguage)
        defaults.set("preserved", forKey: SettingsKey.panelTabs)
        PanelView.prepareLatestReleasePreview(defaults)
        XCTAssertFalse(defaults.bool(forKey: "newsSeen.2.5.3"))
        XCTAssertEqual(defaults.integer(forKey: "newsShown.2.5.3"), 0)
        XCTAssertNil(defaults.object(forKey: "newsFirstShown.2.5.3"))
        XCTAssertTrue(defaults.bool(forKey: "newsSeen.2.5"))
        XCTAssertTrue(defaults.bool(forKey: "newsSeen.2.4.5"))
        XCTAssertEqual(defaults.string(forKey: SettingsKey.appLanguage), "de")
        XCTAssertEqual(defaults.string(forKey: SettingsKey.panelTabs), "preserved")
    }

    func testHotfixesHaveNotesButNoPanelCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.3.2"))
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.3.2 – "))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.3.1"))
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.3.1 – "))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.2.1"))
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.2.1 – "))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.1.8"))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.1.7"))
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.1.8 – "))
    }

    func testEveryLanguageKeepsThePanelAndInputHotfixWithoutANewCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.4.1"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.4.1 – "), lang.rawValue)
            let current = notes.components(separatedBy: "2.4.1 – ")[1].components(separatedBy: "2.4.0 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 3, lang.rawValue)
        }
    }

    func testEveryLanguageKeepsTheTrackerHotfixWithoutANewCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.4.2"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.4.2 – "), lang.rawValue)
            let current = notes.components(separatedBy: "2.4.2 – ")[1].components(separatedBy: "2.4.1 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 1, lang.rawValue)
        }
    }

    func testEveryLanguageKeepsTheTorrentAndSessionHotfixWithoutANewCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.4.3"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.4.3 – "), lang.rawValue)
            let current = notes.components(separatedBy: "2.4.3 – ")[1].components(separatedBy: "2.4.2 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 2, lang.rawValue)
        }
    }

    func testEveryLanguageKeepsTheDurationInputHotfixWithoutANewCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.4.4"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.4.4 – "), lang.rawValue)
            let current = notes.components(separatedBy: "2.4.4 – ")[1].components(separatedBy: "2.4.3 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 2, lang.rawValue)
        }
    }

    func testMenuBarPatchReleaseHasItsExplicitCardAndNotesInEveryLanguage() {
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.4.5"))

        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.contains("2.4.5 – 2026-11-12"), lang.rawValue)
            let current = notes.components(separatedBy: "2.4.5 – ")[1].components(separatedBy: "2.4.4 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 3, lang.rawValue)
        }
    }

    func testSpacingPatchHasNoNewAnnouncementCopyOrPanelCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.4.6"))
        for lang in AppLanguage.allCases {
            XCTAssertTrue(L10n.t(.docNews, lang).contains("2.4.6 – 2026-11-14\n\n2.4.5 – "), lang.rawValue)
        }
    }

    func testTheMinorReleaseHasItsCard() {
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.4.0 – "))
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.4"))
        XCTAssertEqual(ReleaseNews.preparing(notes: L10n.t(.docNews, .en), cards: PanelView.releaseCardIDs), "2.5.3")
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.3.0 – "))
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.3"))
    }

    func testEveryLanguageKeepsTheMixerCardCopyInTheMinorRelease() {
        for lang in AppLanguage.allCases {
            let firstItem = L10n.t(.docNews, lang).components(separatedBy: "2.4.0 – ")[1].components(separatedBy: "\n\n")[1]
            XCTAssertEqual(firstItem, "• " + L10n.t(.news24Mixer, lang), lang.rawValue)
        }
    }

    func testEveryLanguageKeepsTheAIItemInTheMinorRelease() {
        for lang in AppLanguage.allCases {
            let items = L10n.t(.docNews, lang).components(separatedBy: "2.4.0 – ")[1].components(separatedBy: "\n\n")
            XCTAssertEqual(items[2], "• " + L10n.t(.news24AI, lang), lang.rawValue)
            XCTAssertFalse(L10n.t(.news24AI, lang).isEmpty, lang.rawValue)
            XCTAssertNotEqual(L10n.t(.news24AI, lang), L10nKey.news24AI.rawValue, lang.rawValue)
        }
    }

    func testTheNetworkReleaseHasItsCard() {
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.2.0 – "))
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.2"))
    }
    func testPatch253HasItsCardAndLocalizedNotesInEveryLanguage() {
        XCTAssertEqual(PanelView.releaseCardIDs.last, "2.5.3")
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.hasPrefix("2.5.3 – 2026-11-18"), lang.rawValue)
            for item in L10n.patch253Text(lang) { XCTAssertTrue(notes.contains("• " + item), lang.rawValue) }
        }
    }
}
