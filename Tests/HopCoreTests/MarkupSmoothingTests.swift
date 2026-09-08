import XCTest
@testable import HopCore

final class MarkupSmoothingTests: XCTestCase {
    private func line(_ count: Int) -> [MarkupPoint] {
        (0..<count).map { MarkupPoint(x: Double($0) * 10, y: 0) }
    }

    func testEveryLegEndsOnAPointThatWasDrawn() {
        let points = [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 10, y: 20),
                      MarkupPoint(x: 30, y: 5), MarkupPoint(x: 50, y: 40)]
        let legs = MarkupGeometry.curves(through: points)
        XCTAssertEqual(legs.count, 3)
        XCTAssertEqual(legs.map(\.to), Array(points.dropFirst()))
    }

    /// Smoothing must not bend a straight line: the controls stay on it.
    func testAStraightStrokeStaysStraight() {
        for leg in MarkupGeometry.curves(through: line(5)) {
            XCTAssertEqual(leg.control1.y, 0, accuracy: 0.0001)
            XCTAssertEqual(leg.control2.y, 0, accuracy: 0.0001)
        }
    }

    /// The ends are anchored: the first control leans on the first point, so a
    /// stroke does not fly off before it starts.
    func testTheFirstAndLastLegsLeanOnTheirOwnEnds() {
        let points = [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 10, y: 0), MarkupPoint(x: 20, y: 10)]
        let legs = MarkupGeometry.curves(through: points)
        XCTAssertEqual(legs.first?.control1.x ?? -1, 10.0 / 6, accuracy: 0.0001)
        XCTAssertEqual(legs.last?.to, MarkupPoint(x: 20, y: 10))
    }

    func testTooFewPointsMakeNoCurves() {
        XCTAssertTrue(MarkupGeometry.curves(through: []).isEmpty)
        XCTAssertTrue(MarkupGeometry.curves(through: [MarkupPoint(x: 1, y: 1)]).isEmpty)
    }

    /// A slow hand reports a cluster of points in one place; taking them all
    /// leaves the smoothing fighting noise it was handed.
    func testAPointOnTopOfTheLastOneIsNotWorthTaking() {
        let last = MarkupPoint(x: 100, y: 100)
        XCTAssertFalse(MarkupGeometry.worthAdding(MarkupPoint(x: 100.5, y: 100), after: last))
        XCTAssertTrue(MarkupGeometry.worthAdding(MarkupPoint(x: 104, y: 100), after: last))
    }
}
