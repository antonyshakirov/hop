import XCTest
@testable import HopCore

final class MarkupDocumentTests: XCTestCase {
    private func stroke(_ tool: MarkupTool = .pencil) -> MarkupShape {
        MarkupShape(tool: tool,
                    points: [MarkupPoint(x: 0, y: 0), MarkupPoint(x: 10, y: 10)],
                    ink: MarkupInk(hex: "#FF453A", width: 3),
                    createdAt: 0)
    }

    func testUndoTakesTheLastShapeOffAndRedoPutsItBack() {
        let doc = MarkupDocument()
        doc.add(stroke())
        doc.add(stroke(.marker))
        XCTAssertEqual(doc.shapes.count, 2)

        doc.undo()
        XCTAssertEqual(doc.shapes.count, 1)
        XCTAssertEqual(doc.shapes.first?.tool, .pencil)

        doc.redo()
        XCTAssertEqual(doc.shapes.count, 2)
        XCTAssertEqual(doc.shapes.last?.tool, .marker)
    }

    /// A new mark after an undo is a new branch: what was undone is gone for
    /// good, so redo must not resurrect a shape the user drew over.
    func testDrawingAfterUndoDropsTheRedoStack() {
        let doc = MarkupDocument()
        doc.add(stroke())
        doc.undo()
        doc.add(stroke(.arrow))

        XCTAssertFalse(doc.canRedo)
        XCTAssertEqual(doc.shapes.map(\.tool), [.arrow])
    }

    func testUndoOnAnEmptyDocumentIsNotAnError() {
        let doc = MarkupDocument()
        doc.undo()
        XCTAssertTrue(doc.shapes.isEmpty)
        XCTAssertFalse(doc.canUndo)
    }

    /// Moving a step circle is one undo step, not two: the drag replaces the
    /// shape in place.
    func testUpdatingAShapeIsOneUndoStep() {
        let doc = MarkupDocument()
        var shape = stroke(.steps)
        doc.add(shape)
        shape.points = [MarkupPoint(x: 40, y: 40)]
        doc.update(shape)

        XCTAssertEqual(doc.shapes.first?.points.first?.x, 40)
        doc.undo()
        XCTAssertEqual(doc.shapes.first?.points.first?.x, 0)
    }

    func testClearIsUndoable() {
        let doc = MarkupDocument()
        doc.add(stroke())
        doc.add(stroke(.oval))
        doc.clear()
        XCTAssertTrue(doc.shapes.isEmpty)

        doc.undo()
        XCTAssertEqual(doc.shapes.count, 2)
    }

    /// The eraser removes whole shapes, and taking one out of the middle must
    /// leave the rest in the order they were drawn.
    func testRemovingAShapeKeepsTheOrderOfTheRest() {
        let doc = MarkupDocument()
        let first = stroke(.pencil)
        let middle = stroke(.arrow)
        let last = stroke(.oval)
        doc.add(first)
        doc.add(middle)
        doc.add(last)

        doc.remove(id: middle.id)
        XCTAssertEqual(doc.shapes.map(\.tool), [.pencil, .oval])
    }

    /// A document nobody drew on has nothing to take back: an empty change must
    /// not push a history entry that swallows a later undo.
    func testAChangeThatChangesNothingLeavesNoHistory() {
        let doc = MarkupDocument()
        doc.add(stroke())
        doc.remove(id: UUID())

        XCTAssertTrue(doc.canUndo)
        doc.undo()
        XCTAssertTrue(doc.shapes.isEmpty)
    }

    /// Erasing a step circle renumbers the rest, and taking that back must
    /// restore both at once.
    func testAChangeToSeveralShapesIsOneUndo() {
        let doc = MarkupDocument()
        var first = stroke(.steps); first.step = 1
        var second = stroke(.steps); second.step = 2
        doc.add(first)
        doc.add(second)

        doc.apply { $0.filter { $0.step != 1 }.map { shape in
            var renumbered = shape
            renumbered.step = 1
            return renumbered
        } }
        XCTAssertEqual(doc.shapes.compactMap(\.step), [1])

        doc.undo()
        XCTAssertEqual(doc.shapes.compactMap(\.step), [1, 2])
    }

    // MARK: - Ink that has faded

    /// SPEC: docs/spec.md — "Draw over the screen", fading ink. A faded stroke
    /// kept in the history came back invisible on undo, one press per stroke.
    func testForgottenMarksLeaveTheHistoryToo() {
        let doc = MarkupDocument()
        doc.add(stroke(.arrow))
        doc.add(stroke(.fadingInk))
        doc.add(stroke(.fadingInk))

        doc.forget { $0.tool == .fadingInk }

        XCTAssertEqual(doc.shapes.map(\.tool), [.arrow])
        doc.undo()
        XCTAssertTrue(doc.shapes.isEmpty)
        XCTAssertFalse(doc.canUndo)
    }

    func testForgettingKeepsWhatIsStillToRedo() {
        let doc = MarkupDocument()
        doc.add(stroke(.fadingInk))
        doc.add(stroke(.arrow))
        doc.add(stroke(.oval))
        doc.undo()

        doc.forget { $0.tool == .fadingInk }

        XCTAssertEqual(doc.shapes.map(\.tool), [.arrow])
        doc.redo()
        XCTAssertEqual(doc.shapes.map(\.tool), [.arrow, .oval])
        doc.undo()
        doc.undo()
        XCTAssertTrue(doc.shapes.isEmpty)
        XCTAssertFalse(doc.canUndo)
    }

    /// SPEC: docs/spec.md — closing the drawing layer ends its session.
    func testAResetLeavesNothingToUndoOrRedo() {
        let doc = MarkupDocument()
        doc.add(stroke())
        doc.add(stroke(.oval))
        doc.undo()

        doc.reset()

        XCTAssertTrue(doc.shapes.isEmpty)
        XCTAssertFalse(doc.canUndo)
        XCTAssertFalse(doc.canRedo)
    }
}
