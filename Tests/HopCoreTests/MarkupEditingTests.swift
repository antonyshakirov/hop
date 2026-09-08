import XCTest
@testable import HopCore

final class MarkupEditingTests: XCTestCase {
    private func shape(_ tool: MarkupTool, _ points: [MarkupPoint]) -> MarkupShape {
        MarkupShape(tool: tool, points: points,
                    ink: MarkupInk(hex: "#FF453A", width: 4), createdAt: 0)
    }

    func testALineIsPulledByItsTwoEnds() {
        let line = shape(.line, [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 10, y: 10)])
        XCTAssertEqual(MarkupEditing.handles(of: line).count, 2)
        let pulled = MarkupEditing.pulled(line, handle: 1, to: MarkupPoint(x: 40, y: 5))
        XCTAssertEqual(pulled.points[0], MarkupPoint(x: 0, y: 0))
        XCTAssertEqual(pulled.points[1], MarkupPoint(x: 40, y: 5))
    }

    func testABoxIsPulledByFourCorners() {
        let box = shape(.rectangle, [MarkupPoint(x: 10, y: 10), MarkupPoint(x: 30, y: 20)])
        let corners = MarkupEditing.handles(of: box)
        XCTAssertEqual(corners, [MarkupPoint(x: 10, y: 10), MarkupPoint(x: 30, y: 10),
                                 MarkupPoint(x: 30, y: 20), MarkupPoint(x: 10, y: 20)])
    }

    /// The corner across from the one being held is the one that must not move.
    func testPullingACornerLeavesTheOppositeOneWhereItWas() {
        let box = shape(.rectangle, [MarkupPoint(x: 10, y: 10), MarkupPoint(x: 30, y: 20)])
        let pulled = MarkupEditing.pulled(box, handle: 0, to: MarkupPoint(x: 0, y: 4))
        let corners = MarkupEditing.handles(of: pulled)
        XCTAssertEqual(corners[2], MarkupPoint(x: 30, y: 20))
        XCTAssertEqual(corners[0], MarkupPoint(x: 0, y: 4))
    }

    func testAScribbleHasNoHandlesAndIsNotReshaped() {
        let scribble = shape(.pencil, (0..<20).map { MarkupPoint(x: Double($0), y: 0) })
        XCTAssertTrue(MarkupEditing.handles(of: scribble).isEmpty)
        XCTAssertEqual(MarkupEditing.pulled(scribble, handle: 0, to: MarkupPoint(x: 99, y: 99)).points,
                       scribble.points)
    }

    func testMovingCarriesEveryPointTheSameWay() {
        let scribble = shape(.marker, [MarkupPoint(x: 1, y: 2), MarkupPoint(x: 5, y: 9)])
        let moved = MarkupEditing.moved(scribble, by: MarkupPoint(x: -3, y: 4))
        XCTAssertEqual(moved.points, [MarkupPoint(x: -2, y: 6), MarkupPoint(x: 2, y: 13)])
    }

    func testAnOutOfRangeHandleChangesNothing() {
        let line = shape(.line, [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 10, y: 10)])
        XCTAssertEqual(MarkupEditing.pulled(line, handle: 7, to: MarkupPoint(x: 1, y: 1)).points,
                       line.points)
    }
}
