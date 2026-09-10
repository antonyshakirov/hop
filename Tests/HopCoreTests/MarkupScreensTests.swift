import XCTest
@testable import HopCore

final class MarkupScreensTests: XCTestCase {
    private func mark(on display: UInt32?) -> MarkupShape {
        MarkupShape(tool: .rectangle,
                    points: [MarkupPoint(x: 10, y: 10), MarkupPoint(x: 90, y: 60)],
                    ink: MarkupInk(hex: "#FF453A", width: 4),
                    display: display, createdAt: 0)
    }

    /// A mark drawn on one monitor sat at the same spot on every other one.
    func testAMonitorShowsOnlyTheMarksDrawnOnIt() {
        let left = mark(on: 1), right = mark(on: 2)
        XCTAssertEqual(MarkupScreens.on(1, [left, right]), [left])
        XCTAssertEqual(MarkupScreens.on(2, [left, right]), [right])
    }

    /// The editor has one picture and no monitor to tell apart.
    func testASurfaceWithNoMonitorShowsEverything() {
        let marks = [mark(on: 1), mark(on: 2), mark(on: nil)]
        XCTAssertEqual(MarkupScreens.on(nil, marks), marks)
    }

    func testAMarkWithNoMonitorBelongsToEveryOne() {
        XCTAssertTrue(MarkupScreens.belongs(mark(on: nil), to: 3))
        XCTAssertTrue(MarkupScreens.belongs(mark(on: 3), to: 3))
        XCTAssertFalse(MarkupScreens.belongs(mark(on: 4), to: 3))
    }
}
