import XCTest
@testable import HopCore

final class WatermarkTests: XCTestCase {
    private let frame = MarkupPoint(x: 1000, y: 600)
    private let mark = MarkupPoint(x: 200, y: 60)

    func testEveryCornerKeepsTheSameInset() {
        let inset = 24.0
        let topLeading = Watermark.origin(of: mark, in: frame, spot: .topLeading, inset: inset)
        XCTAssertEqual(topLeading.x, inset)
        XCTAssertEqual(topLeading.y, inset)

        let bottomTrailing = Watermark.origin(of: mark, in: frame, spot: .bottomTrailing, inset: inset)
        XCTAssertEqual(bottomTrailing.x, frame.x - mark.x - inset)
        XCTAssertEqual(bottomTrailing.y, frame.y - mark.y - inset)
    }

    func testTheOtherTwoCornersMirrorTheFirstTwo() {
        let inset = 24.0
        let topTrailing = Watermark.origin(of: mark, in: frame, spot: .topTrailing, inset: inset)
        XCTAssertEqual(topTrailing.x, frame.x - mark.x - inset)
        XCTAssertEqual(topTrailing.y, inset)

        let bottomLeading = Watermark.origin(of: mark, in: frame, spot: .bottomLeading, inset: inset)
        XCTAssertEqual(bottomLeading.x, inset)
        XCTAssertEqual(bottomLeading.y, frame.y - mark.y - inset)
    }

    func testTheCentreIgnoresTheInset() {
        let centre = Watermark.origin(of: mark, in: frame, spot: .centre, inset: 24)
        XCTAssertEqual(centre.x, (frame.x - mark.x) / 2, accuracy: 0.001)
        XCTAssertEqual(centre.y, (frame.y - mark.y) / 2, accuracy: 0.001)
    }

    /// Stamps laid edge to edge read as a wall; the step leaves air between.
    func testTilingLeavesAirBetweenTheStamps() {
        let step = Watermark.tileStep(of: mark, spread: 80)
        XCTAssertGreaterThan(step.x, mark.x)
        XCTAssertGreaterThan(step.y, mark.y)
    }

    /// Size and count are separate wishes: a big mark repeated rarely is a
    /// real one, and the spread is what says how rarely.
    func testTheSpreadSetsHowOftenTheMarkRepeats() {
        let mark = MarkupPoint(x: 100, y: 40)
        let tight = Watermark.tileStep(of: mark, spread: 10)
        let loose = Watermark.tileStep(of: mark, spread: 300)
        XCTAssertGreaterThan(loose.x, tight.x)
        XCTAssertGreaterThan(tight.x, mark.x, "stamps must never sit on each other")
    }

    func testAnAbsurdSpreadIsBroughtBackIntoRange() {
        let mark = MarkupPoint(x: 10, y: 10)
        XCTAssertEqual(Watermark.tileStep(of: mark, spread: -500),
                       Watermark.tileStep(of: mark, spread: 10))
        XCTAssertEqual(Watermark.tileStep(of: mark, spread: 5000),
                       Watermark.tileStep(of: mark, spread: 300))
    }

    /// The mark is measured against the shorter side, so it does not swell to
    /// the width of a panorama.
    func testTheMarkIsMeasuredAgainstTheShorterSide() {
        var watermark = Watermark.standard
        watermark.size = 10
        let wide = Watermark.height(in: MarkupPoint(x: 4000, y: 600), watermark: watermark)
        let tall = Watermark.height(in: MarkupPoint(x: 600, y: 4000), watermark: watermark)
        XCTAssertEqual(wide, tall, accuracy: 0.001)
    }

    func testAMarkTurnedOffIsNotStamped() {
        XCTAssertFalse(Watermark.standard.isOn)
        XCTAssertFalse(Watermark.standard.hasSomethingToStamp)
    }

    /// Text switched on but left empty stamps nothing, instead of an invisible
    /// rectangle in the corner.
    func testEmptyTextStampsNothing() {
        var watermark = Watermark.standard
        watermark.isOn = true
        XCTAssertFalse(watermark.hasSomethingToStamp)

        watermark.text = "hop.tools"
        XCTAssertTrue(watermark.hasSomethingToStamp)
    }
}
