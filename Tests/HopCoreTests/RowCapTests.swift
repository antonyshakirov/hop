import XCTest
import CoreGraphics
@testable import HopCore

/// Per-module "visible rows" cap (to-dos + tracker): always active, 3…15, with a
/// default of 10; a stored 0 (the previous "all" sentinel) reads as the default.
final class RowCapTests: XCTestCase {

    func testDefaultIsTen() {
        XCTAssertEqual(RowCap.defaultRows, 10)
    }

    func testZeroOrNegativeReadsAsDefault() {
        // 0 was the old "all" sentinel — it now reads as the default cap, not "no cap"
        XCTAssertEqual(RowCap.cap(0), RowCap.defaultRows)
        XCTAssertEqual(RowCap.cap(-3), RowCap.defaultRows)
    }

    func testInRangeIsKept() {
        XCTAssertEqual(RowCap.cap(3), 3)
        XCTAssertEqual(RowCap.cap(10), 10)
        XCTAssertEqual(RowCap.cap(15), 15)
    }

    func testBelowMinClampsUpAndAboveMaxClampsDown() {
        // a legacy/edge value of 1 or 2 is > 0 — clamp up to 3
        XCTAssertEqual(RowCap.cap(1), 3)
        XCTAssertEqual(RowCap.cap(2), 3)
        XCTAssertEqual(RowCap.cap(99), 15)
    }

    func testStoredZeroCapsAtTheDefault() {
        // 100 rows with the "all" sentinel now scroll at 10 (287pt), not uncapped
        XCTAssertEqual(RowCap.listHeight(stored: 0, count: 100), 287)
        XCTAssertTrue(RowCap.scrolls(stored: 0, count: 100))
    }

    func testListHeightNilWhenListFitsUnderCap() {
        XCTAssertNil(RowCap.listHeight(stored: 10, count: 5))
        XCTAssertNil(RowCap.listHeight(stored: 10, count: 10), "exactly at the cap still fits")
    }

    func testListHeightIsCapRowsPlusInterRowGapsWhenOverflowing() {
        // The list VStack uses spacing:3, so exactly `cap` rows also need their
        // (cap − 1) gaps — height is 29·cap − 3, not 26·cap.
        XCTAssertEqual(RowCap.listHeight(stored: 8, count: 9),
                       8 * (RowCap.rowHeight + RowCap.rowSpacing) - RowCap.rowSpacing)
        XCTAssertEqual(RowCap.listHeight(stored: 8, count: 9), 229)
        XCTAssertEqual(RowCap.listHeight(stored: 3, count: 50), 84)
        XCTAssertEqual(RowCap.listHeight(stored: 10, count: 11), 287)
    }

    func testRowHeightAndSpacingAreIntegral() {
        // fractional heights caused the header-jump bug — the cap height must be whole
        XCTAssertEqual(RowCap.rowHeight, RowCap.rowHeight.rounded())
        XCTAssertEqual(RowCap.rowSpacing, RowCap.rowSpacing.rounded())
    }

    func testListHeightIsIntegralForEveryCap() {
        for cap in RowCap.minRows...RowCap.maxRows {
            let h = RowCap.listHeight(stored: cap, count: cap + 1)
            XCTAssertNotNil(h)
            XCTAssertEqual(h, h?.rounded(), "cap \(cap) height must be whole")
        }
    }

    func testScrollsMirrorsListHeight() {
        XCTAssertFalse(RowCap.scrolls(stored: 10, count: 10))
        XCTAssertTrue(RowCap.scrolls(stored: 8, count: 9))
    }
}
