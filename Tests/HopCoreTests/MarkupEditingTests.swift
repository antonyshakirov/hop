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

extension MarkupEditingTests {
    /// A rectangle is picked up from ANYWHERE inside it: aiming a mouse at a
    /// one-point outline is not a thing anyone can do.
    func testABoxIsGrabbedFromInsideIt() {
        let box = MarkupShape(tool: .rectangle,
                              points: [MarkupPoint(x: 10, y: 10), MarkupPoint(x: 90, y: 60)],
                              ink: MarkupInk(hex: "#FF453A", width: 4), createdAt: 0)
        XCTAssertTrue(MarkupEditing.grabbed(box, at: MarkupPoint(x: 50, y: 35), tolerance: 8))
        XCTAssertFalse(MarkupEditing.grabbed(box, at: MarkupPoint(x: 200, y: 35), tolerance: 8))
    }

    /// A line has no inside, so it is still taken by proximity.
    func testALineIsGrabbedNearItAndNotAcrossTheGap() {
        let line = MarkupShape(tool: .line,
                               points: [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 100, y: 0)],
                               ink: MarkupInk(hex: "#FF453A", width: 4), createdAt: 0)
        XCTAssertTrue(MarkupEditing.grabbed(line, at: MarkupPoint(x: 50, y: 3), tolerance: 8))
        XCTAssertFalse(MarkupEditing.grabbed(line, at: MarkupPoint(x: 50, y: 60), tolerance: 8))
    }

    func testANumberedStepIsGrabbedByItsCircle() {
        let step = MarkupShape(tool: .steps, points: [MarkupPoint(x: 40, y: 40)],
                               ink: MarkupInk(hex: "#FF453A", width: 2), step: 1, createdAt: 0)
        XCTAssertTrue(MarkupEditing.grabbed(step, at: MarkupPoint(x: 48, y: 45), tolerance: 2))
        XCTAssertFalse(MarkupEditing.grabbed(step, at: MarkupPoint(x: 90, y: 40), tolerance: 2))
    }
}

extension MarkupEditingTests {
    private func lens(_ centre: (Double, Double), _ radius: Double) -> MarkupShape {
        MarkupShape(tool: .magnifier,
                    points: [MarkupPoint(x: centre.0 - radius, y: centre.1 - radius),
                             MarkupPoint(x: centre.0 + radius, y: centre.1 + radius)],
                    ink: MarkupInk(hex: "#FFFFFF", width: 5), createdAt: 0)
    }

    /// A round thing is held at its four bearings, ON the circle.
    func testALensIsHeldAtItsFourBearings() {
        let spots = MarkupEditing.handles(of: lens((100, 100), 40))
        XCTAssertEqual(spots, [MarkupPoint(x: 100, y: 60), MarkupPoint(x: 140, y: 100),
                               MarkupPoint(x: 100, y: 140), MarkupPoint(x: 60, y: 100)])
    }

    /// It grows about its own middle: there is no corner to anchor it by.
    func testALensGrowsAboutItsMiddle() {
        let pulled = MarkupEditing.pulled(lens((100, 100), 40), handle: 1,
                                          to: MarkupPoint(x: 190, y: 100))
        let after = MarkupEditing.lens(of: pulled)
        XCTAssertEqual(after?.centre, MarkupPoint(x: 100, y: 100))
        XCTAssertEqual(after?.radius ?? 0, 90, accuracy: 0.001)
    }

    func testALensNeverShrinksToNothing() {
        let pulled = MarkupEditing.pulled(lens((100, 100), 40), handle: 0,
                                          to: MarkupPoint(x: 100, y: 100))
        XCTAssertEqual(MarkupEditing.lens(of: pulled)?.radius ?? 0, 12, accuracy: 0.001)
    }
}
