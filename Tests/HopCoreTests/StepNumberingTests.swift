import XCTest
@testable import HopCore

final class StepNumberingTests: XCTestCase {
    private func step(_ number: Int, x: Double, at time: TimeInterval? = nil) -> MarkupShape {
        MarkupShape(tool: .steps, points: [MarkupPoint(x: x, y: 0)],
                    ink: MarkupInk(hex: "#FF453A", width: 2),
                    step: number, createdAt: time ?? Double(number))
    }

    func testTheFirstStepIsOne() {
        XCTAssertEqual(StepNumbering.next(in: []), 1)
    }

    func testTheNextStepFollowsTheHighestOnTheFrame() {
        XCTAssertEqual(StepNumbering.next(in: [step(1, x: 0), step(2, x: 10)]), 3)
    }

    /// Deleting the middle circle must leave 1, 2, 3 — not 1, 3.
    func testDeletingAStepClosesTheGap() {
        let left = [step(1, x: 0), step(3, x: 20), step(4, x: 30)]
        XCTAssertEqual(StepNumbering.renumbered(left).compactMap(\.step), [1, 2, 3])
    }

    /// The order is the order they were PLACED, not where they sit.
    func testDraggingAStepDoesNotChangeItsNumber() {
        var second = step(2, x: 10)
        second.points = [MarkupPoint(x: -500, y: -500)]
        let numbered = StepNumbering.renumbered([step(1, x: 0), second, step(3, x: 20)])
        XCTAssertEqual(numbered.compactMap(\.step), [1, 2, 3])
    }

    /// The list is drawing order; a circle placed earlier keeps the lower
    /// number even when it was added to the array last.
    func testTheNumbersFollowWhenTheyWerePlaced() {
        let late = step(1, x: 0, at: 50)
        let early = step(2, x: 10, at: 10)
        XCTAssertEqual(StepNumbering.renumbered([late, early]).compactMap(\.step), [2, 1])
    }

    func testOtherToolsAreLeftAlone() {
        let pencil = MarkupShape(tool: .pencil, points: [], ink: MarkupInk(hex: "#FFFFFF", width: 2), createdAt: 0)
        let numbered = StepNumbering.renumbered([pencil, step(5, x: 0)])
        XCTAssertNil(numbered.first?.step)
        XCTAssertEqual(numbered.last?.step, 1)
    }

    func testAFrameWithoutStepsIsReturnedUntouched() {
        let pencil = MarkupShape(tool: .pencil, points: [], ink: MarkupInk(hex: "#FFFFFF", width: 2), createdAt: 0)
        XCTAssertEqual(StepNumbering.renumbered([pencil]), [pencil])
    }
}
