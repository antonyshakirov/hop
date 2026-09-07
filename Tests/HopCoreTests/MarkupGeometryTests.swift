import XCTest
@testable import HopCore

final class MarkupGeometryTests: XCTestCase {
    private let start = MarkupPoint(x: 0, y: 0)
    private let end = MarkupPoint(x: 100, y: 0)

    /// An arrow whose head overshoots the tip reads as a miss.
    func testTheArrowHeadSitsBehindTheTip() {
        for style in ArrowStyle.allCases {
            let head = MarkupGeometry.arrowHead(from: start, to: end, style: style, width: 3)
            XCTAssertFalse(head.isEmpty, "\(style) drew no head")
            for point in head {
                XCTAssertLessThanOrEqual(point.x, end.x + 0.001, "\(style) overshot the tip")
            }
        }
    }

    func testTheThinHeadIsSymmetricAroundTheShaft() {
        let head = MarkupGeometry.arrowHead(from: start, to: end, style: .thin, width: 3)
        let above = head.filter { $0.y < -0.001 }.count
        let below = head.filter { $0.y > 0.001 }.count
        XCTAssertEqual(above, below)
    }

    func testAZeroLengthArrowDrawsNoHead() {
        XCTAssertTrue(MarkupGeometry.arrowHead(from: start, to: start, style: .solid, width: 3).isEmpty)
    }

    /// A head sized for another width reads as a dart, or disappears.
    func testTheHeadGrowsWithTheLineWidth() {
        let thin = MarkupGeometry.arrowHead(from: start, to: end, style: .solid, width: 2)
        let fat = MarkupGeometry.arrowHead(from: start, to: end, style: .solid, width: 8)
        let thinReach = thin.map { end.x - $0.x }.max() ?? 0
        let fatReach = fat.map { end.x - $0.x }.max() ?? 0
        XCTAssertGreaterThan(fatReach, thinReach)
    }

    func testTheBoundingBoxSurvivesPointsGivenInAnyOrder() {
        let box = MarkupGeometry.boundingBox([
            MarkupPoint(x: 30, y: 50), MarkupPoint(x: 10, y: 90),
        ])
        XCTAssertEqual(box.origin.x, 10)
        XCTAssertEqual(box.origin.y, 50)
        XCTAssertEqual(box.size.x, 20)
        XCTAssertEqual(box.size.y, 40)
    }

    func testAnEmptyShapeHasAnEmptyBox() {
        let box = MarkupGeometry.boundingBox([])
        XCTAssertEqual(box.size.x, 0)
        XCTAssertEqual(box.size.y, 0)
    }

    /// The eraser takes whole shapes: near hits, a finger away misses.
    func testTheEraserFindsAStrokeItIsNear() {
        let stroke = MarkupShape(tool: .pencil,
                                 points: [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 100, y: 0)],
                                 ink: MarkupInk(hex: "#FFFFFF", width: 2),
                                 createdAt: 0)
        XCTAssertTrue(MarkupGeometry.hits(shape: stroke, point: MarkupPoint(x: 50, y: 3), tolerance: 6))
        XCTAssertFalse(MarkupGeometry.hits(shape: stroke, point: MarkupPoint(x: 50, y: 40), tolerance: 6))
    }

    /// Tolerance is measured from the ink's edge, not its centre line.
    func testAFatStrokeIsEasierToHit() {
        let hairline = MarkupShape(tool: .pencil,
                                   points: [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 100, y: 0)],
                                   ink: MarkupInk(hex: "#FFFFFF", width: 1),
                                   createdAt: 0)
        var fat = hairline
        fat.ink.width = 20
        let point = MarkupPoint(x: 50, y: 12)
        XCTAssertFalse(MarkupGeometry.hits(shape: hairline, point: point, tolerance: 4))
        XCTAssertTrue(MarkupGeometry.hits(shape: fat, point: point, tolerance: 4))
    }

    /// A rectangle is two corners; the eraser tests the box they stand for.
    func testARectangleIsHitAnywhereOnItsFrame() {
        let box = MarkupShape(tool: .rectangle,
                              points: [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 100, y: 60)],
                              ink: MarkupInk(hex: "#FFFFFF", width: 2),
                              createdAt: 0)
        XCTAssertTrue(MarkupGeometry.hits(shape: box, point: MarkupPoint(x: 50, y: 1), tolerance: 4))
        XCTAssertFalse(MarkupGeometry.hits(shape: box, point: MarkupPoint(x: 50, y: 30), tolerance: 4))
    }

    func testALassoKnowsInsideFromOutside() {
        let square = [
            MarkupPoint(x: 0, y: 0), MarkupPoint(x: 10, y: 0),
            MarkupPoint(x: 10, y: 10), MarkupPoint(x: 0, y: 10),
        ]
        XCTAssertTrue(MarkupGeometry.contains(polygon: square, point: MarkupPoint(x: 5, y: 5)))
        XCTAssertFalse(MarkupGeometry.contains(polygon: square, point: MarkupPoint(x: 15, y: 5)))
    }

    /// A horseshoe's notch is outside, or blur covers what was left out.
    func testAConcaveLassoLeavesItsNotchOutside() {
        let horseshoe = [
            MarkupPoint(x: 0, y: 0), MarkupPoint(x: 30, y: 0), MarkupPoint(x: 30, y: 30),
            MarkupPoint(x: 20, y: 30), MarkupPoint(x: 20, y: 10), MarkupPoint(x: 10, y: 10),
            MarkupPoint(x: 10, y: 30), MarkupPoint(x: 0, y: 30),
        ]
        XCTAssertTrue(MarkupGeometry.contains(polygon: horseshoe, point: MarkupPoint(x: 5, y: 20)))
        XCTAssertFalse(MarkupGeometry.contains(polygon: horseshoe, point: MarkupPoint(x: 15, y: 20)))
    }
}
