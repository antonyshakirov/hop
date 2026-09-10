import XCTest
@testable import HopCore

final class MarkupShapeTests: XCTestCase {
    /// The renderers tell a filled head from an open one by the count alone, so
    /// the count is the contract between the geometry and the drawing.
    func testTheSolidHeadIsATriangleAndTheOthersAreBarbs() {
        let from = MarkupPoint(x: 0, y: 0)
        let to = MarkupPoint(x: 100, y: 0)
        XCTAssertEqual(MarkupGeometry.arrowHead(from: from, to: to, style: .solid, width: 3).count, 3)
        XCTAssertEqual(MarkupGeometry.arrowHead(from: from, to: to, style: .thin, width: 3).count, 2)
        XCTAssertEqual(MarkupGeometry.arrowHead(from: from, to: to, style: .freehand, width: 3).count, 2)
    }

    func testAShapeRemembersTheHeadItWasDrawnWith() throws {
        let shape = MarkupShape(tool: .arrow,
                                points: [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 10, y: 10)],
                                ink: MarkupInk(hex: "#FF453A", width: 4),
                                arrow: .thin,
                                createdAt: 0)
        let back = try JSONDecoder().decode(MarkupShape.self, from: JSONEncoder().encode(shape))
        XCTAssertEqual(back.arrow, .thin)
    }

    /// Marks written before arrows had styles must still open: the field is
    /// absent from that JSON, and a required one would fail the whole document.
    func testAMarkSavedBeforeArrowStylesStillDecodes() throws {
        let json = """
        {
          "id": "8B0C6F9E-6C0E-4E0A-9E9C-7D3E9A1F2B45",
          "tool": "arrow",
          "points": [{"x": 0, "y": 0}, {"x": 10, "y": 10}],
          "ink": {"hex": "#FF453A", "width": 4},
          "createdAt": 0
        }
        """
        let shape = try JSONDecoder().decode(MarkupShape.self, from: Data(json.utf8))
        XCTAssertNil(shape.arrow)
        XCTAssertNil(shape.display)
    }

    func testAShapeRemembersTheMonitorItWasDrawnOn() throws {
        let shape = MarkupShape(tool: .pencil, points: [MarkupPoint(x: 0, y: 0)],
                                ink: MarkupInk(hex: "#FF453A", width: 4),
                                display: 7, createdAt: 0)
        let back = try JSONDecoder().decode(MarkupShape.self, from: JSONEncoder().encode(shape))
        XCTAssertEqual(back.display, 7)
    }
}
