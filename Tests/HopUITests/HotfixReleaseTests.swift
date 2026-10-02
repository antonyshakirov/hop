import XCTest
@testable import Hop

@MainActor
final class HotfixReleaseTests: XCTestCase {
    func testHotfixesHaveNotesButNoPanelCard() {
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.3.2"))
        XCTAssertTrue(L10n.t(.docNews, .en).hasPrefix("2.3.2 – "))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.3.1"))
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.3.1 – "))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.2.1"))
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.2.1 – "))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.1.8"))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.1.7"))
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.1.8 – "))
    }

    func testTheMinorReleaseHasItsCard() {
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.3.0 – "))
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.3"))
    }

    func testTheNetworkReleaseHasItsCard() {
        XCTAssertTrue(L10n.t(.docNews, .en).contains("2.2.0 – "))
        XCTAssertTrue(PanelView.releaseCardIDs.contains("2.2"))
    }
}
