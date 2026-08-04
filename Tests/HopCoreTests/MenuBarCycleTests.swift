import XCTest
@testable import HopCore

final class MenuBarCycleTests: XCTestCase {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    // MARK: - Whose turn it is

    func testASingleReadingKeepsTheLine() {
        // nothing to take turns with: the answer is the same at every moment
        XCTAssertEqual(MenuBarCycle.index(count: 1, now: date(0)), 0)
        XCTAssertEqual(MenuBarCycle.index(count: 1, now: date(7.3)), 0)
        XCTAssertEqual(MenuBarCycle.index(count: 1, now: date(999)), 0)
    }

    func testTwoReadingsAlternateEveryFiveSeconds() {
        XCTAssertEqual(MenuBarCycle.index(count: 2, now: date(0)), 0)
        XCTAssertEqual(MenuBarCycle.index(count: 2, now: date(4.9)), 0)
        XCTAssertEqual(MenuBarCycle.index(count: 2, now: date(5)), 1)
        XCTAssertEqual(MenuBarCycle.index(count: 2, now: date(9.9)), 1)
        XCTAssertEqual(MenuBarCycle.index(count: 2, now: date(10)), 0)
    }

    func testThreeReadingsGoRound() {
        XCTAssertEqual(MenuBarCycle.index(count: 3, now: date(2)), 0)
        XCTAssertEqual(MenuBarCycle.index(count: 3, now: date(7)), 1)
        XCTAssertEqual(MenuBarCycle.index(count: 3, now: date(12)), 2)
        XCTAssertEqual(MenuBarCycle.index(count: 3, now: date(17)), 0)
    }

    func testTheTurnIsAFunctionOfTheClockNotOfCallOrder() {
        // two redraws at the same instant must agree, and a redraw that arrives
        // late must not shift the rotation
        let moment = date(123.4)
        XCTAssertEqual(MenuBarCycle.index(count: 2, now: moment),
                       MenuBarCycle.index(count: 2, now: moment))
    }

    // MARK: - The handover

    func testTheDigitsAreFullyLegibleThroughTheMiddleOfATurn() {
        XCTAssertEqual(MenuBarCycle.opacity(now: date(2.5)), 1)
        XCTAssertEqual(MenuBarCycle.opacity(now: date(7.5)), 1)
    }

    func testTheDigitsVanishExactlyOnTheBoundary() {
        XCTAssertEqual(MenuBarCycle.opacity(now: date(5)), 0, accuracy: 0.0001)
        XCTAssertEqual(MenuBarCycle.opacity(now: date(10)), 0, accuracy: 0.0001)
    }

    func testTheFadeIsHalfOutAndHalfIn() {
        // a quarter second either side of the boundary, half legible
        XCTAssertEqual(MenuBarCycle.opacity(now: date(4.875)), 0.5, accuracy: 0.01)
        XCTAssertEqual(MenuBarCycle.opacity(now: date(5.125)), 0.5, accuracy: 0.01)
    }

    func testOpacityNeverLeavesItsRange() {
        for step in stride(from: 0.0, through: 20.0, by: 0.05) {
            let value = MenuBarCycle.opacity(now: date(step))
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    // MARK: - When the fine tick is needed

    func testTheFineTickIsAskedForJustBeforeAHandover() {
        // the fade starts a quarter second before the boundary
        XCTAssertEqual(MenuBarCycle.untilFade(now: date(1)), 3.75, accuracy: 0.001)
        XCTAssertEqual(MenuBarCycle.untilFade(now: date(4.5)), 0.25, accuracy: 0.001)
    }

    func testInsideTheFadeThereIsNothingToWaitFor() {
        XCTAssertEqual(MenuBarCycle.untilFade(now: date(4.9)), 0, accuracy: 0.001)
        XCTAssertEqual(MenuBarCycle.untilFade(now: date(5)), 0, accuracy: 0.001)
        // and while the digits are still climbing back in
        XCTAssertEqual(MenuBarCycle.untilFade(now: date(5.1)), 0, accuracy: 0.001)
    }
}
