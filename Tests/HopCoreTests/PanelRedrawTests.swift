import XCTest
@testable import HopCore

final class PanelRedrawTests: XCTestCase {
    private let panel = "panel"
    private let settings = "settings"

    func testNothingOnScreenTakesNoTicks() {
        var redraw = PanelRedraw()
        XCTAssertFalse(redraw.ticks())
        XCTAssertFalse(redraw.ticks())
    }

    func testAVisibleSurfaceTakesEveryTick() {
        var redraw = PanelRedraw()
        _ = redraw.setVisible(true, surface: panel)
        XCTAssertTrue(redraw.ticks())
        XCTAssertTrue(redraw.ticks())
    }

    func testAppearingOwesOneRedrawForTheTicksItMissed() {
        var redraw = PanelRedraw()
        _ = redraw.ticks()
        XCTAssertTrue(redraw.setVisible(true, surface: panel))
    }

    func testAppearingWithNothingMissedOwesNothing() {
        var redraw = PanelRedraw()
        XCTAssertFalse(redraw.setVisible(true, surface: panel))
    }

    func testTheSameSurfaceReportingTwiceOwesNothingTheSecondTime() {
        var redraw = PanelRedraw()
        _ = redraw.ticks()
        XCTAssertTrue(redraw.setVisible(true, surface: panel))
        XCTAssertFalse(redraw.setVisible(true, surface: panel))
    }

    func testTheSameSurfaceLeavingTwiceDoesNotUncoverTheOther() {
        var redraw = PanelRedraw()
        _ = redraw.setVisible(true, surface: panel)
        _ = redraw.setVisible(true, surface: settings)
        _ = redraw.setVisible(false, surface: panel)
        _ = redraw.setVisible(false, surface: panel)
        XCTAssertTrue(redraw.ticks(), "the settings window is still on screen")
    }

    func testTicksGoOnWhileAnySurfaceRemains() {
        var redraw = PanelRedraw()
        _ = redraw.setVisible(true, surface: panel)
        _ = redraw.setVisible(true, surface: settings)
        _ = redraw.setVisible(false, surface: panel)
        XCTAssertTrue(redraw.ticks())
        _ = redraw.setVisible(false, surface: settings)
        XCTAssertFalse(redraw.ticks())
    }

    func testTheSecondSurfaceToAppearOwesNothing() {
        var redraw = PanelRedraw()
        _ = redraw.ticks()
        XCTAssertTrue(redraw.setVisible(true, surface: panel))
        XCTAssertFalse(redraw.setVisible(true, surface: settings))
    }

    func testTicksTakenWhileVisibleAreNotOwedOnTheNextAppearance() {
        var redraw = PanelRedraw()
        _ = redraw.setVisible(true, surface: panel)
        _ = redraw.ticks()
        _ = redraw.setVisible(false, surface: panel)
        XCTAssertFalse(redraw.setVisible(true, surface: panel))
    }

    func testGoingAwayNeverOwesARedraw() {
        var redraw = PanelRedraw()
        _ = redraw.ticks()
        XCTAssertFalse(redraw.setVisible(false, surface: panel))
    }
}
