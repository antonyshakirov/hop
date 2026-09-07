import Foundation

/// SPEC: .claude/specs/2026-09-07-markup-modules-design.md
public enum ArrowStyle: String, Codable, CaseIterable, Sendable {
    case thin
    case solid
    case freehand
}

/// Shapes of the markup tools, and the hit-testing the eraser asks for.
/// Tests: Tests/HopCoreTests/MarkupGeometryTests.swift
public enum MarkupGeometry {
    /// The barbs of a thin arrow, the triangle of a solid one. Empty for a line
    /// too short to carry a head.
    public static func arrowHead(
        from: MarkupPoint, to: MarkupPoint, style: ArrowStyle, width: Double
    ) -> [MarkupPoint] {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length >= 4 else { return [] }

        let angle = atan2(dy, dx)
        let reach = max(12, width * 4.6)

        func back(_ spread: Double, _ scale: Double) -> MarkupPoint {
            MarkupPoint(x: to.x - cos(angle - spread) * reach * scale,
                        y: to.y - sin(angle - spread) * reach * scale)
        }

        switch style {
        case .thin:
            return [back(0.46, 1), back(-0.46, 1)]
        case .solid:
            return [back(0.42, 1), MarkupPoint(x: to.x - cos(angle) * reach * 0.62,
                                               y: to.y - sin(angle) * reach * 0.62), back(-0.42, 1)]
        case .freehand:
            return [back(0.52, 0.95), back(-0.38, 0.85)]
        }
    }

    public static func boundingBox(_ points: [MarkupPoint]) -> (origin: MarkupPoint, size: MarkupPoint) {
        guard let first = points.first else {
            return (MarkupPoint(x: 0, y: 0), MarkupPoint(x: 0, y: 0))
        }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return (MarkupPoint(x: minX, y: minY), MarkupPoint(x: maxX - minX, y: maxY - minY))
    }

    /// Tolerance is measured from the ink's edge, so a fat stroke is a wider
    /// target than a hairline.
    public static func hits(shape: MarkupShape, point: MarkupPoint, tolerance: Double) -> Bool {
        let reach = tolerance + shape.ink.width / 2

        switch shape.tool {
        case .rectangle, .oval, .blur, .crop, .magnifier:
            return onFrame(of: shape, point: point, reach: reach)
        case .steps, .text:
            guard let centre = shape.points.first else { return false }
            return distance(centre, point) <= max(reach, 16)
        default:
            return onStroke(of: shape, point: point, reach: reach)
        }
    }

    /// Ray casting: a point is inside when a ray leaving it crosses the outline
    /// an odd number of times, which holds for concave lassos too.
    public static func contains(polygon: [MarkupPoint], point: MarkupPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y) {
                let cut = (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x
                if point.x < cut { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    private static func onStroke(of shape: MarkupShape, point: MarkupPoint, reach: Double) -> Bool {
        guard shape.points.count > 1 else {
            guard let only = shape.points.first else { return false }
            return distance(only, point) <= reach
        }
        for index in 0..<(shape.points.count - 1) {
            if distance(from: point, toSegment: shape.points[index], shape.points[index + 1]) <= reach {
                return true
            }
        }
        return false
    }

    private static func onFrame(of shape: MarkupShape, point: MarkupPoint, reach: Double) -> Bool {
        let box = boundingBox(shape.points)
        let corners = [
            MarkupPoint(x: box.origin.x, y: box.origin.y),
            MarkupPoint(x: box.origin.x + box.size.x, y: box.origin.y),
            MarkupPoint(x: box.origin.x + box.size.x, y: box.origin.y + box.size.y),
            MarkupPoint(x: box.origin.x, y: box.origin.y + box.size.y),
        ]
        for index in corners.indices {
            let next = corners[(index + 1) % corners.count]
            if distance(from: point, toSegment: corners[index], next) <= reach { return true }
        }
        return false
    }

    private static func distance(_ a: MarkupPoint, _ b: MarkupPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private static func distance(from point: MarkupPoint, toSegment a: MarkupPoint, _ b: MarkupPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(a, point) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        return distance(MarkupPoint(x: a.x + t * dx, y: a.y + t * dy), point)
    }
}
