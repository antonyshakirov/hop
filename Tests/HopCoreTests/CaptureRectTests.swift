import XCTest
@testable import HopCore

final class CaptureRectTests: XCTestCase {
    func testDraggingBackwardsGivesTheSameRectangle() {
        let downRight = CaptureRect.normalized(from: MarkupPoint(x: 10, y: 10),
                                               to: MarkupPoint(x: 110, y: 60),
                                               scale: 2, displayID: 1)
        let upLeft = CaptureRect.normalized(from: MarkupPoint(x: 110, y: 60),
                                            to: MarkupPoint(x: 10, y: 10),
                                            scale: 2, displayID: 1)
        XCTAssertEqual(downRight, upLeft)
        XCTAssertEqual(downRight.x, 10)
        XCTAssertEqual(downRight.width, 100)
    }

    /// Points are what the mouse gives; a capture asked in points comes back
    /// half size on a retina display.
    func testPixelSizeFollowsTheDisplayScale() {
        let retina = CaptureRect(x: 0, y: 0, width: 100, height: 50, scale: 2, displayID: 1)
        XCTAssertEqual(retina.pixelWidth, 200)
        XCTAssertEqual(retina.pixelHeight, 100)

        let plain = CaptureRect(x: 0, y: 0, width: 100, height: 50, scale: 1, displayID: 2)
        XCTAssertEqual(plain.pixelWidth, 100)
    }

    func testASelectionDraggedOffTheDisplayIsCutAtItsEdge() {
        let screen = CaptureRect(x: 0, y: 0, width: 1440, height: 900, scale: 2, displayID: 1)
        let rect = CaptureRect(x: 1400, y: 880, width: 200, height: 200, scale: 2, displayID: 1)
        let clamped = rect.clamped(to: screen)
        XCTAssertEqual(clamped.width, 40)
        XCTAssertEqual(clamped.height, 20)
    }

    /// A selection wholly off the display is not a negative rectangle.
    func testASelectionOutsideTheDisplayCollapsesToNothing() {
        let screen = CaptureRect(x: 0, y: 0, width: 1440, height: 900, scale: 2, displayID: 1)
        let away = CaptureRect(x: 2000, y: 2000, width: 100, height: 100, scale: 2, displayID: 1)
        let clamped = away.clamped(to: screen)
        XCTAssertEqual(clamped.width, 0)
        XCTAssertEqual(clamped.height, 0)
        XCTAssertFalse(clamped.isUsable)
    }

    func testAClickWithoutADragIsNotACapture() {
        let dot = CaptureRect.normalized(from: MarkupPoint(x: 5, y: 5),
                                         to: MarkupPoint(x: 6, y: 6),
                                         scale: 2, displayID: 1)
        XCTAssertFalse(dot.isUsable)
    }

    /// The second display can carry another scale, and the rectangle must keep
    /// the one it was drawn on.
    func testTheRectangleRemembersItsOwnDisplay() {
        let onSecond = CaptureRect.normalized(from: MarkupPoint(x: 0, y: 0),
                                              to: MarkupPoint(x: 100, y: 100),
                                              scale: 1, displayID: 7)
        XCTAssertEqual(onSecond.displayID, 7)
        XCTAssertEqual(onSecond.pixelWidth, 100)
    }
}
