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
        case .magnifier:
            // A round thing is held at its four bearings, ON the circle. Corners
            // of a box it does not have are corners of nothing.
            guard let lens = lens(of: shape) else { return [] }
            return [MarkupPoint(x: lens.centre.x, y: lens.centre.y - lens.radius),
                    MarkupPoint(x: lens.centre.x + lens.radius, y: lens.centre.y),
                    MarkupPoint(x: lens.centre.x, y: lens.centre.y + lens.radius),
                    MarkupPoint(x: lens.centre.x - lens.radius, y: lens.centre.y)]
        case .rectangle, .oval, .blur, .crop:
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

    /// Picking a mark up is done by its AREA, not by its outline: nobody aims a
    /// mouse at a hairline. Strokes, lines and arrows keep proximity — their
    /// area IS the line.
    public static func grabbed(_ shape: MarkupShape, at point: MarkupPoint, tolerance: Double) -> Bool {
        switch shape.tool {
        case .rectangle, .oval, .blur, .magnifier, .crop:
            guard shape.points.count > 1 else { return false }
            let box = MarkupGeometry.boundingBox(shape.points)
            return inside(box, point, pad: tolerance)
        case .steps:
            guard let centre = shape.points.first else { return false }
            let dx = centre.x - point.x, dy = centre.y - point.y
            return (dx * dx + dy * dy).squareRoot() <= 17 + tolerance
        case .text:
            guard let origin = shape.points.first else { return false }
            let height = shape.ink.width * 1.4
            let width = max(40, Double(shape.text?.count ?? 0) * shape.ink.width * 0.62)
            return inside((origin: origin, size: MarkupPoint(x: width, y: height)),
                          point, pad: tolerance)
        default:
            return MarkupGeometry.hits(shape: shape, point: point, tolerance: tolerance)
        }
    }

    private static func inside(
        _ box: (origin: MarkupPoint, size: MarkupPoint), _ point: MarkupPoint, pad: Double
    ) -> Bool {
        point.x >= box.origin.x - pad && point.x <= box.origin.x + box.size.x + pad
            && point.y >= box.origin.y - pad && point.y <= box.origin.y + box.size.y + pad
    }

    /// The dial round a lens. SPEC: docs/spec.md
    public enum Zoom {
        /// Degrees clockwise from due east, y counting DOWN.
        public static let start = 22.0
        public static let end = 74.0
        public static let least = 1.5
        public static let most = 6.0
        public static let gap = 11.0

        public static func of(_ shape: MarkupShape) -> Double {
            min(max(shape.magnification ?? 2, least), most)
        }

        public static func knob(of shape: MarkupShape) -> MarkupPoint? {
            guard let lens = MarkupEditing.lens(of: shape) else { return nil }
            let share = (of(shape) - least) / (most - least)
            return spot(on: lens, degrees: start + (end - start) * share)
        }

        /// Off the ends of the arc, the ends.
        public static func asked(
            at point: MarkupPoint, lens: (centre: MarkupPoint, radius: Double)
        ) -> Double {
            let angle = atan2(point.y - lens.centre.y, point.x - lens.centre.x) * 180 / .pi
            let share = (angle - start) / (end - start)
            return least + (most - least) * min(max(share, 0), 1)
        }

        public static func spot(
            on lens: (centre: MarkupPoint, radius: Double), degrees: Double
        ) -> MarkupPoint {
            let radians = degrees * .pi / 180
            let reach = lens.radius + gap
            return MarkupPoint(x: lens.centre.x + cos(radians) * reach,
                               y: lens.centre.y + sin(radians) * reach)
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
        case .magnifier:
            // The lens grows about its own middle: it has no corner to anchor.
            guard let lens = lens(of: shape) else { return shape }
            let dx = point.x - lens.centre.x, dy = point.y - lens.centre.y
            let radius = max(12, (dx * dx + dy * dy).squareRoot())
            pulled.points = [MarkupPoint(x: lens.centre.x - radius, y: lens.centre.y - radius),
                             MarkupPoint(x: lens.centre.x + radius, y: lens.centre.y + radius)]
        case .rectangle, .oval, .blur, .crop:
            let opposite = spots[(index + 2) % 4]
            pulled.points = [opposite, point]
        default:
            return shape
        }
        return pulled
    }

    /// The circle a lens really is: the biggest that fits its box, on the same
    /// middle.
    public static func lens(of shape: MarkupShape) -> (centre: MarkupPoint, radius: Double)? {
        guard shape.points.count > 1 else { return nil }
        let box = MarkupGeometry.boundingBox(shape.points)
        let radius = min(box.size.x, box.size.y) / 2
        guard radius > 0 else { return nil }
        return (MarkupPoint(x: box.origin.x + box.size.x / 2,
                            y: box.origin.y + box.size.y / 2), radius)
    }

    private static func boundingBox(_ points: [MarkupPoint]) -> (origin: MarkupPoint, size: MarkupPoint) {
        MarkupGeometry.boundingBox(points)
    }
}
