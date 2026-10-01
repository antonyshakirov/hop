import XCTest
@testable import Hop

final class PanelHeightLimitTests: XCTestCase {
    func testCeilingLeavesTheMarginBelowTheMenuBar() {
        XCTAssertEqual(PanelHeightLimit.ceiling(screenVisibleHeight: 1410), 1386)
    }

    func testCeilingWithoutAScreenFallsBackToASmallOne() {
        XCTAssertEqual(PanelHeightLimit.ceiling(screenVisibleHeight: nil), 776)
    }

    func testPanelTallerThanItsScreenIsCutToTheCeiling() {
        let asked = CGSize(width: 368, height: 2174)
        let clamped = PanelHeightLimit.clamp(asked, screenVisibleHeight: 1410)
        XCTAssertEqual(clamped, CGSize(width: 368, height: 1386))
    }

    func testPanelThatFitsKeepsItsSize() {
        let asked = CGSize(width: 368, height: 540)
        XCTAssertEqual(PanelHeightLimit.clamp(asked, screenVisibleHeight: 1410), asked)
    }

    func testSizeIsUntouchedWhileNoScreenIsRecorded() {
        let asked = CGSize(width: 368, height: 2174)
        XCTAssertEqual(PanelHeightLimit.clamp(asked, screenVisibleHeight: nil), asked)
    }

    func testClipboardCeilingFollowsThePanelScreenNotTheTallerOne() {
        XCTAssertEqual(PanelHeightLimit.clipboardCeiling(screenVisibleHeight: 870), 310)
        XCTAssertEqual(PanelHeightLimit.clipboardCeiling(screenVisibleHeight: 1410), 430)
    }

    func testClipboardCeilingNeverDropsBelowAFewRows() {
        XCTAssertEqual(PanelHeightLimit.clipboardCeiling(screenVisibleHeight: 600), 208)
    }
}
