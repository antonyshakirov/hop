import Foundation
import XCTest
@testable import Hop

final class PanelPopoverGeometryTests: XCTestCase {
    private let visible = CGRect(x: 1440, y: 90, width: 1512, height: 860)

    func testGrowthAfterAddingVPNKeepsTheOriginalTopEdge() {
        let previous = CGRect(x: 2300, y: 480, width: 394, height: 460)
        let displaced = CGRect(x: 2300, y: 590, width: 394, height: 560)
        let result = PanelPopoverGeometry.anchoredFrame(
            displaced, top: previous.maxY, visibleFrame: visible)
        XCTAssertEqual(result.maxY, previous.maxY)
        XCTAssertTrue(visible.contains(result))
    }

    func testRemovingModulesShrinksDownFromTheSameTopWithoutCumulativeDrift() {
        var frame = CGRect(x: 2300, y: 380, width: 394, height: 560)
        let top = frame.maxY
        for height: CGFloat in [460, 560, 460, 560, 460] {
            frame.size.height = height
            frame = PanelPopoverGeometry.anchoredFrame(frame, top: top, visibleFrame: visible)
            XCTAssertEqual(frame.maxY, top)
        }
    }

    func testScreenChangeClampsTheTopToTheCurrentVisibleScreen() {
        let frame = CGRect(x: 2300, y: 700, width: 394, height: 460)
        let result = PanelPopoverGeometry.anchoredFrame(frame, top: 1160, visibleFrame: visible)
        XCTAssertEqual(result.maxY, visible.maxY)
        XCTAssertTrue(visible.contains(result))
    }

    func testOversizedFrameKeepsItsTopAccessibleAfterMovingToAShorterScreen() {
        let frame = CGRect(x: 2300, y: 300, width: 394, height: 1200)
        let result = PanelPopoverGeometry.anchoredFrame(frame, top: frame.maxY,
                                                       visibleFrame: visible)
        XCTAssertEqual(result.maxY, visible.maxY)
        XCTAssertEqual(result.size, frame.size)
    }

    func testNormallyAnchoredFrameNeedsNoCorrection() {
        let frame = CGRect(x: 2300, y: 480, width: 394, height: 460)
        XCTAssertEqual(PanelPopoverGeometry.anchoredFrame(frame, top: frame.maxY,
                                                        visibleFrame: visible), frame)
    }
}
