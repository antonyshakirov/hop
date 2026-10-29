import XCTest
import HopCore
@testable import Hop

@MainActor
final class HotfixReleaseTests: XCTestCase {
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

    func testEveryLanguageOpensWithThePanelAndInputHotfixWithoutANewCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.4.1"))
        for lang in AppLanguage.allCases {
            let notes = L10n.t(.docNews, lang)
            XCTAssertTrue(notes.hasPrefix("2.4.1 – "), lang.rawValue)
            let current = notes.components(separatedBy: "2.4.0 – ")[0]
            XCTAssertEqual(current.components(separatedBy: "• ").count - 1, 3, lang.rawValue)
        }
    }

    func testTheMinorReleaseHasItsCard() {
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.4.0 – "))
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.4"))
        XCTAssertEqual(ReleaseNews.preparing(notes: L10n.t(.docNews, .en), cards: PanelView.releaseCardIDs), "2.4.1")
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
}
