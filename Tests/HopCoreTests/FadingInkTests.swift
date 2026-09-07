import XCTest
@testable import HopCore

final class FadingInkTests: XCTestCase {
    private func ink(at time: TimeInterval, tool: MarkupTool = .fadingInk) -> MarkupShape {
        MarkupShape(tool: tool, points: [], ink: MarkupInk(hex: "#FFD60A", width: 3), createdAt: time)
    }

    func testAFreshStrokeIsFullyOpaque() {
        XCTAssertEqual(FadingInk.opacity(of: ink(at: 0), now: 0), 1, accuracy: 0.001)
        XCTAssertEqual(FadingInk.opacity(of: ink(at: 0), now: FadingInk.life - 0.01), 1, accuracy: 0.001)
    }

    func testItThinsOutWhileItFades() {
        let middle = FadingInk.opacity(of: ink(at: 0), now: FadingInk.life + FadingInk.fade / 2)
        XCTAssertEqual(middle, 0.5, accuracy: 0.05)
    }

    func testItIsGoneAfterItsLifeAndFade() {
        let gone = FadingInk.life + FadingInk.fade + 0.01
        XCTAssertEqual(FadingInk.opacity(of: ink(at: 0), now: gone), 0, accuracy: 0.001)
        XCTAssertTrue(FadingInk.alive([ink(at: 0)], now: gone).isEmpty)
    }

    func testEveryOtherToolIgnoresTheClock() {
        let pencil = ink(at: 0, tool: .pencil)
        XCTAssertEqual(FadingInk.opacity(of: pencil, now: 10_000), 1, accuracy: 0.001)
        XCTAssertEqual(FadingInk.alive([pencil], now: 10_000).count, 1)
    }

    /// A layer full of pencil strokes must keep no schedule alive; that is the
    /// CPU cost the performance budget forbids.
    func testTheTimerRunsOnlyWhileSomethingIsFading() {
        XCTAssertTrue(FadingInk.needsTicking([ink(at: 0)], now: 0.2))
        XCTAssertFalse(FadingInk.needsTicking([ink(at: 0)], now: FadingInk.life + FadingInk.fade + 1))
        XCTAssertFalse(FadingInk.needsTicking([ink(at: 0, tool: .marker)], now: 0.2))
        XCTAssertFalse(FadingInk.needsTicking([], now: 0))
    }

    func testOneLivingStrokeAmongDeadOnesKeepsTheTimer() {
        let shapes = [ink(at: 0), ink(at: 100)]
        XCTAssertTrue(FadingInk.needsTicking(shapes, now: 100.1))
        XCTAssertEqual(FadingInk.alive(shapes, now: 100.1).count, 1)
    }
}
