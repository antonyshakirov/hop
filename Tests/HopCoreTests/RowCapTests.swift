import XCTest
import CoreGraphics
@testable import HopCore

/// Per-module "visible rows" cap (to-dos + tracker): 0 = all (default, no cap);
/// 3…15 caps the list to a fixed, integral height with internal scroll.
final class RowCapTests: XCTestCase {

    func testZeroOrNegativeMeansAll() {
        XCTAssertNil(RowCap.cap(0))
        XCTAssertNil(RowCap.cap(-3))
    }

    func testInRangeIsKept() {
        XCTAssertEqual(RowCap.cap(3), 3)
        XCTAssertEqual(RowCap.cap(8), 8)
        XCTAssertEqual(RowCap.cap(15), 15)
    }

    func testBelowMinClampsUpAndAboveMaxClampsDown() {
        // a legacy/edge value of 1 or 2 is not "all" (it is > 0) — clamp up to 3
        XCTAssertEqual(RowCap.cap(1), 3)
        XCTAssertEqual(RowCap.cap(2), 3)
        XCTAssertEqual(RowCap.cap(99), 15)
    }

    func testListHeightNilWhenUncapped() {
        XCTAssertNil(RowCap.listHeight(stored: 0, count: 100))
    }

    func testListHeightNilWhenListFitsUnderCap() {
        // capped at 8 but only 5 rows — no scroll, natural height
        XCTAssertNil(RowCap.listHeight(stored: 8, count: 5))
        XCTAssertNil(RowCap.listHeight(stored: 8, count: 8), "exactly at the cap still fits")
    }

    func testListHeightIsCapTimesRowHeightWhenOverflowing() {
        XCTAssertEqual(RowCap.listHeight(stored: 8, count: 9), 8 * RowCap.rowHeight)
        XCTAssertEqual(RowCap.listHeight(stored: 3, count: 50), 3 * RowCap.rowHeight)
    }

    func testRowHeightIsIntegral() {
        // fractional heights caused the header-jump bug — the cap height must be whole
        XCTAssertEqual(RowCap.rowHeight, RowCap.rowHeight.rounded())
    }

    func testScrollsMirrorsListHeight() {
        XCTAssertFalse(RowCap.scrolls(stored: 0, count: 100))
        XCTAssertFalse(RowCap.scrolls(stored: 8, count: 8))
        XCTAssertTrue(RowCap.scrolls(stored: 8, count: 9))
    }
}
