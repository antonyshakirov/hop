import Foundation

/// The only door into the marks on one surface; views read `shapes` and never
/// edit them. A change that changes nothing pushes no history.
/// SPEC: .claude/specs/2026-09-07-markup-modules-design.md
/// Tests: Tests/HopCoreTests/MarkupDocumentTests.swift
public final class MarkupDocument {
    public private(set) var shapes: [MarkupShape] = []
    private var past: [[MarkupShape]] = []
    private var future: [[MarkupShape]] = []

    public init() {}

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    public func add(_ shape: MarkupShape) {
        commit { $0.append(shape) }
    }

    public func update(_ shape: MarkupShape) {
        commit { list in
            guard let index = list.firstIndex(where: { $0.id == shape.id }) else { return }
            list[index] = shape
        }
    }

    public func remove(id: UUID) {
        commit { $0.removeAll { $0.id == id } }
    }

    public func clear() {
        commit { $0.removeAll() }
    }

    /// One history entry for a change that touches several marks at once —
    /// erasing a step circle and renumbering the rest is one undo, not two.
    public func apply(_ transform: ([MarkupShape]) -> [MarkupShape]) {
        commit { $0 = transform($0) }
    }

    public func undo() {
        guard let previous = past.popLast() else { return }
        future.append(shapes)
        shapes = previous
    }

    public func redo() {
        guard let next = future.popLast() else { return }
        past.append(shapes)
        shapes = next
    }

    private func commit(_ change: (inout [MarkupShape]) -> Void) {
        var next = shapes
        change(&next)
        guard next != shapes else { return }
        past.append(shapes)
        future.removeAll()
        shapes = next
    }
}
