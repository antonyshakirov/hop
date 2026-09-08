import Foundation

/// A mark already on the canvas: where it can be pulled, and what pulling it
/// does. Freehand strokes and single-point marks have no handles — they move
/// whole, because reshaping a scribble point by point is not markup.
/// SPEC: docs/spec.md — "Screenshot (capture and mark up)"
/// Tests: Tests/HopCoreTests/MarkupEditingTests.swift
public enum MarkupEditing {
    public static func handles(of shape: MarkupShape) -> [MarkupPoint] {
        switch shape.tool {
        case .arrow, .line:
            guard shape.points.count > 1 else { return [] }
            return [shape.points[0], shape.points[1]]
        case .rectangle, .oval, .blur, .magnifier, .crop:
            guard shape.points.count > 1 else { return [] }
            let box = boundingBox(shape.points)
            let left = box.origin.x, top = box.origin.y
            let right = left + box.size.x, bottom = top + box.size.y
            return [MarkupPoint(x: left, y: top), MarkupPoint(x: right, y: top),
                    MarkupPoint(x: right, y: bottom), MarkupPoint(x: left, y: bottom)]
        default:
            return []
        }
    }

    public static func moved(_ shape: MarkupShape, by delta: MarkupPoint) -> MarkupShape {
        var moved = shape
        moved.points = shape.points.map { MarkupPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return moved
    }

    /// The handle goes where it is put; for a box the corner ACROSS from it
    /// stays where it was, so the shape grows out of the one being held.
    public static func pulled(_ shape: MarkupShape, handle index: Int, to point: MarkupPoint) -> MarkupShape {
        var pulled = shape
        let spots = handles(of: shape)
        guard spots.indices.contains(index) else { return shape }

        switch shape.tool {
        case .arrow, .line:
            guard pulled.points.count > 1 else { return shape }
            pulled.points[index] = point
        case .rectangle, .oval, .blur, .magnifier, .crop:
            let opposite = spots[(index + 2) % 4]
            pulled.points = [opposite, point]
        default:
            return shape
        }
        return pulled
    }

    private static func boundingBox(_ points: [MarkupPoint]) -> (origin: MarkupPoint, size: MarkupPoint) {
        MarkupGeometry.boundingBox(points)
    }
}
