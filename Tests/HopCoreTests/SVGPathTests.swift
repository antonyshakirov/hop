import CoreGraphics
import XCTest
@testable import HopCore

final class SVGPathTests: XCTestCase {
    // MARK: - Helpers

    private func endpoint(_ op: SVGPath.Op) -> CGPoint? {
        switch op {
        case .move(let p), .line(let p): return p
        default: return nil
        }
    }

    private func assertMove(_ op: SVGPath.Op, _ x: CGFloat, _ y: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .move(let p) = op else {
            return XCTFail("expected .move, got \(op)", file: file, line: line)
        }
        XCTAssertEqual(p.x, x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: 0.0001, file: file, line: line)
    }

    private func assertLine(_ op: SVGPath.Op, _ x: CGFloat, _ y: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard case .line(let p) = op else {
            return XCTFail("expected .line, got \(op)", file: file, line: line)
        }
        XCTAssertEqual(p.x, x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(p.y, y, accuracy: 0.0001, file: file, line: line)
    }

    // MARK: - Tests

    func testMoveThenLine() {
        let ops = SVGPath.parse("M10 20 L30 40")
        XCTAssertEqual(ops.count, 2)
        assertMove(ops[0], 10, 20)
        assertLine(ops[1], 30, 40)
    }

    func testImplicitLineto() {
        // A second coordinate set after M is an implicit lineto.
        let ops = SVGPath.parse("M0 0 10 10")
        XCTAssertEqual(ops.count, 2)
        assertMove(ops[0], 0, 0)
        assertLine(ops[1], 10, 10)
    }

    func testRelativeMoveAndLine() {
        let ops = SVGPath.parse("m5 5 l10 0")
        XCTAssertEqual(ops.count, 2)
        assertMove(ops[0], 5, 5)
        assertLine(ops[1], 15, 5)
    }

    func testHorizontalAndVertical() {
        let ops = SVGPath.parse("M0 0 H10 V5")
        XCTAssertEqual(ops.count, 3)
        assertMove(ops[0], 0, 0)
        assertLine(ops[1], 10, 0)
        assertLine(ops[2], 10, 5)
    }

    func testNoSpaceNegatives() {
        // ".5-.5" must tokenize as 0.5 and -0.5.
        let ops = SVGPath.parse("M0 0 l.5-.5")
        XCTAssertEqual(ops.count, 2)
        assertMove(ops[0], 0, 0)
        assertLine(ops[1], 0.5, -0.5)
    }

    func testCloseEmitsCloseOp() {
        let ops = SVGPath.parse("M0 0 L1 1 Z")
        XCTAssertEqual(ops.count, 3)
        XCTAssertEqual(ops.last, .close)
    }

    func testCircularArcSemicircleReachesTarget() {
        // A semicircle from (0,0) to (10,0) with r = 5.
        let ops = SVGPath.parse("M0 0 A5 5 0 0 1 10 0")
        assertMove(ops[0], 0, 0)

        let curves = Array(ops.dropFirst())
        XCTAssertFalse(curves.isEmpty, "arc should expand to at least one cubic")
        for op in curves {
            guard case .cubic = op else {
                return XCTFail("arc should expand only to cubics, got \(op)")
            }
        }
        guard case .cubic(_, _, let end) = ops.last else {
            return XCTFail("expected trailing cubic")
        }
        XCTAssertEqual(end.x, 10, accuracy: 0.01)
        XCTAssertEqual(end.y, 0, accuracy: 0.01)
    }
}
