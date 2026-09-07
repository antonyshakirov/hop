import XCTest
@testable import HopCore

final class PanelRedrawTests: XCTestCase {
    func testHiddenPanelTakesNoTicks() {
        var redraw = PanelRedraw()
        XCTAssertFalse(redraw.ticks())
        XCTAssertFalse(redraw.ticks())
    }

    func testVisiblePanelTakesEveryTick() {
        var redraw = PanelRedraw()
        _ = redraw.setVisible(true)
        XCTAssertTrue(redraw.ticks())
        XCTAssertTrue(redraw.ticks())
    }

    func testAppearingOwesOneRedrawForTheTicksItMissed() {
        var redraw = PanelRedraw()
        _ = redraw.ticks()
        XCTAssertTrue(redraw.setVisible(true))
    }

    func testAppearingWithNothingMissedOwesNothing() {
        var redraw = PanelRedraw()
        XCTAssertFalse(redraw.setVisible(true))
    }

    func testASecondVisibleOwesNothing() {
        var redraw = PanelRedraw()
        _ = redraw.ticks()
        XCTAssertTrue(redraw.setVisible(true))
        XCTAssertFalse(redraw.setVisible(true))
    }

    func testTicksTakenWhileVisibleAreNotOwedOnTheNextAppearance() {
        var redraw = PanelRedraw()
        _ = redraw.setVisible(true)
        _ = redraw.ticks()
        _ = redraw.setVisible(false)
        XCTAssertFalse(redraw.setVisible(true))
    }

    func testGoingAwayNeverOwesARedraw() {
        var redraw = PanelRedraw()
        _ = redraw.ticks()
        XCTAssertFalse(redraw.setVisible(false))
    }
}
