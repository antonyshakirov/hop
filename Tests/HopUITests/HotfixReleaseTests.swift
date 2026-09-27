import XCTest
@testable import Hop

@MainActor
final class HotfixReleaseTests: XCTestCase {
    func testHotfixHasNotesButNoNewPanelCard() {
        XCTAssertTrue(L10n.t(.docNews, .en).hasPrefix("2.1.6"))
        XCTAssertFalse(PanelView.releaseCardIDs.contains("2.1.6"))
    }
}
