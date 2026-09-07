import XCTest
@testable import HopCore

final class FrameDressingTests: XCTestCase {
    private let frame = MarkupPoint(x: 1200, y: 800)

    private func dressed(padding: Int = 8, browser: Bool = false) -> FrameDressing {
        var dressing = FrameDressing.standard
        dressing.isOn = true
        dressing.padding = padding
        dressing.browserFrame = browser
        return dressing
    }

    func testDressingTurnedOffChangesNothing() {
        var off = FrameDressing.standard
        off.isOn = false
        let size = FrameDressing.outputSize(frame: frame, dressing: off)
        XCTAssertEqual(size.x, frame.x)
        XCTAssertEqual(size.y, frame.y)
    }

    /// Padding is a share of the SHORTER side, so one setting reads the same on
    /// a wide shot and a narrow one.
    func testPaddingIsTheSameShareOnBothSides() {
        let wide = FrameDressing.outputSize(frame: MarkupPoint(x: 1200, y: 400),
                                            dressing: dressed(padding: 10))
        XCTAssertEqual(wide.x - 1200, wide.y - 400, accuracy: 0.001)
    }

    func testTheFrameSitsInTheMiddleOfWhatIsAroundIt() {
        let size = FrameDressing.outputSize(frame: frame, dressing: dressed())
        let origin = FrameDressing.frameOrigin(frame: frame, dressing: dressed())
        XCTAssertEqual(origin.x * 2 + frame.x, size.x, accuracy: 0.001)
        XCTAssertEqual(origin.y * 2 + frame.y, size.y, accuracy: 0.001)
    }

    func testNoPaddingLeavesTheFrameItsOwnSize() {
        let size = FrameDressing.outputSize(frame: frame, dressing: dressed(padding: 0))
        XCTAssertEqual(size.x, frame.x)
        XCTAssertEqual(size.y, frame.y)
    }

    /// The browser bar takes height from the dressing, or the shot would be
    /// cropped by its own chrome.
    func testTheBrowserBarAddsHeightAboveTheFrame() {
        let plain = FrameDressing.outputSize(frame: frame, dressing: dressed())
        let chromed = FrameDressing.outputSize(frame: frame, dressing: dressed(browser: true))
        XCTAssertGreaterThan(chromed.y, plain.y)
        XCTAssertEqual(chromed.x, plain.x)
    }

    func testTheBarPushesTheFrameDownByItsOwnHeight() {
        let plainTop = FrameDressing.frameOrigin(frame: frame, dressing: dressed()).y
        let chromed = dressed(browser: true)
        let chromedTop = FrameDressing.frameOrigin(frame: frame, dressing: chromed).y
        XCTAssertEqual(chromedTop - plainTop, FrameDressing.barHeight(frame: frame), accuracy: 0.001)
    }

    /// A tiny shot must not get a bar too thin to draw its dots in.
    func testTheBarNeverGoesBelowItsFloor() {
        XCTAssertEqual(FrameDressing.barHeight(frame: MarkupPoint(x: 100, y: 60)), 34, accuracy: 0.001)
    }
}
