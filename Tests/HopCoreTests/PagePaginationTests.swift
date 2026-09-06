import XCTest
@testable import HopCore

final class PagePaginationTests: XCTestCase {
    private let sheetWidth: Double = 523
    private let sheetHeight: Double = 770

    private func plan(_ width: Double, _ height: Double) -> PagePagination.Plan? {
        PagePagination.plan(contentWidth: width, contentHeight: height,
                            printableWidth: sheetWidth, printableHeight: sheetHeight)
    }

    // MARK: - Fitting the width

    func testAPageWiderThanTheSheetIsScaledDownToIt() {
        let plan = try? XCTUnwrap(plan(1046, 770))
        XCTAssertEqual(plan?.scale ?? 0, 0.5, accuracy: 0.0001)
    }

    func testANarrowPageIsNotBlownUp() {
        XCTAssertEqual(plan(300, 400)?.scale ?? 0, 1, accuracy: 0.0001)
    }

    // MARK: - Slicing down the page

    func testAShortPageIsOneSheet() {
        XCTAssertEqual(plan(523, 400)?.pageCount, 1)
        XCTAssertEqual(plan(523, 770)?.pageCount, 1)
    }

    func testAPageJustOverASheetTakesTwo() {
        XCTAssertEqual(plan(523, 771)?.pageCount, 2)
    }

    func testATallPageIsCutIntoAsManySheetsAsItNeeds() {
        XCTAssertEqual(plan(523, 770 * 3)?.pageCount, 3)
        XCTAssertEqual(plan(523, 770 * 3 + 1)?.pageCount, 4)
    }

    func testTheCountFollowsTheHeightAfterScaling() {
        XCTAssertEqual(plan(1046, 1540)?.pageCount, 1)
    }

    // MARK: - Where each sheet starts

    func testEachSheetStartsOneSheetFurtherDownTheSource() {
        let plan = plan(523, 770 * 3)
        XCTAssertEqual(plan?.sourceOffset(ofPage: 0) ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(plan?.sourceOffset(ofPage: 1) ?? -1, 770, accuracy: 0.0001)
        XCTAssertEqual(plan?.sourceOffset(ofPage: 2) ?? -1, 1540, accuracy: 0.0001)
    }

    func testTheStepIsMeasuredOnTheSourceNotTheSheet() {
        let plan = plan(1046, 1540 * 2)
        XCTAssertEqual(plan?.sourceOffset(ofPage: 1) ?? -1, 1540, accuracy: 0.0001)
    }

    func testAPageWithNoSizeHasNoPlan() {
        XCTAssertNil(plan(0, 500))
        XCTAssertNil(plan(500, 0))
        XCTAssertNil(plan(-1, 500))
    }

    func testAnAbsurdlyTallPageIsRefusedRatherThanPrintedForever() {
        let beyond = Double(PagePagination.pageLimit + 1) * 770
        XCTAssertNil(plan(523, beyond))
    }

    func testAPageExactlyAtTheCapIsStillAllowed() {
        let atCap = Double(PagePagination.pageLimit) * 770
        XCTAssertEqual(plan(523, atCap)?.pageCount, PagePagination.pageLimit)
    }
}
