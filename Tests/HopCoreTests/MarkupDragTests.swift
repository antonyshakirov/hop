import XCTest
@testable import HopCore

final class MarkupDragTests: XCTestCase {
    private let origin = MarkupPoint(x: 100, y: 100)

    func testAPlainDragKeepsBothPointsWhereTheyWere() {
        let points = MarkupDrag.points(tool: .rectangle, origin: origin,
                                       current: MarkupPoint(x: 160, y: 130),
                                       modifiers: .none)
        XCTAssertEqual(points[0], origin)
        XCTAssertEqual(points[1], MarkupPoint(x: 160, y: 130))
    }

    /// Option: the point the drag began on ends up in the middle of the shape.
    func testFromTheCentreMirrorsTheReachAroundTheOrigin() {
        let points = MarkupDrag.points(tool: .oval, origin: origin,
                                       current: MarkupPoint(x: 140, y: 120),
                                       modifiers: .init(fromCentre: true))
        XCTAssertEqual(points[0], MarkupPoint(x: 60, y: 80))
        XCTAssertEqual(points[1], MarkupPoint(x: 140, y: 120))
        XCTAssertEqual((points[0].x + points[1].x) / 2, origin.x)
        XCTAssertEqual((points[0].y + points[1].y) / 2, origin.y)
    }

    /// A square built on the SHORTER side would shrink away from the pointer.
    func testAHeldShiftSquaresTheBoxOnItsLongerSide() {
        let points = MarkupDrag.points(tool: .rectangle, origin: origin,
                                       current: MarkupPoint(x: 190, y: 120),
                                       modifiers: .init(regular: true))
        XCTAssertEqual(points[1], MarkupPoint(x: 190, y: 190))
    }

    func testASquareKeepsTheDirectionItWasDrawnIn() {
        let points = MarkupDrag.points(tool: .rectangle, origin: origin,
                                       current: MarkupPoint(x: 10, y: 80),
                                       modifiers: .init(regular: true))
        XCTAssertEqual(points[1], MarkupPoint(x: 10, y: 10))
    }

    func testAHeldShiftPutsALineOnTheNearestEighth() {
        let points = MarkupDrag.points(tool: .line, origin: origin,
                                       current: MarkupPoint(x: 200, y: 105),
                                       modifiers: .init(regular: true))
        XCTAssertEqual(points[1].y, 100, accuracy: 0.001, "a near-flat line goes flat")
        XCTAssertEqual(points[1].x, 100 + 100.125, accuracy: 0.5)
    }

    func testALineOnTheDiagonalStaysOnIt() {
        let points = MarkupDrag.points(tool: .arrow, origin: origin,
                                       current: MarkupPoint(x: 170, y: 172),
                                       modifiers: .init(regular: true))
        XCTAssertEqual(points[1].x - origin.x, points[1].y - origin.y, accuracy: 0.001)
    }

    func testAFreehandToolIgnoresTheModifiers() {
        let points = MarkupDrag.points(tool: .steps, origin: origin,
                                       current: MarkupPoint(x: 190, y: 120),
                                       modifiers: .init(regular: true))
        XCTAssertEqual(points[1], MarkupPoint(x: 190, y: 120))
    }

    func testBothModifiersTogetherGiveASquareAroundTheOrigin() {
        let points = MarkupDrag.points(tool: .rectangle, origin: origin,
                                       current: MarkupPoint(x: 150, y: 120),
                                       modifiers: .init(fromCentre: true, regular: true))
        XCTAssertEqual(points[0], MarkupPoint(x: 50, y: 50))
        XCTAssertEqual(points[1], MarkupPoint(x: 150, y: 150))
    }
}
