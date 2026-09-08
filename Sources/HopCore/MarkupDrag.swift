import Foundation

/// A two-point drag once the modifier keys have had their say.
/// SPEC: docs/spec.md — "Screenshot (capture and mark up)"
/// Tests: Tests/HopCoreTests/MarkupDragTests.swift
public enum MarkupDrag {
    public struct Modifiers: Equatable, Sendable {
        /// Option: the first point is the centre, not a corner.
        public var fromCentre: Bool
        /// Shift: a box becomes a square, a line snaps to 45°.
        public var regular: Bool

        public init(fromCentre: Bool = false, regular: Bool = false) {
            self.fromCentre = fromCentre
            self.regular = regular
        }

        public static let none = Modifiers()
    }

    public static func points(
        tool: MarkupTool, origin: MarkupPoint, current: MarkupPoint, modifiers: Modifiers
    ) -> [MarkupPoint] {
        var reach = MarkupPoint(x: current.x - origin.x, y: current.y - origin.y)

        if modifiers.regular {
            reach = regularised(tool: tool, reach: reach)
        }

        guard modifiers.fromCentre else {
            return [origin, MarkupPoint(x: origin.x + reach.x, y: origin.y + reach.y)]
        }
        return [MarkupPoint(x: origin.x - reach.x, y: origin.y - reach.y),
                MarkupPoint(x: origin.x + reach.x, y: origin.y + reach.y)]
    }

    private static func regularised(tool: MarkupTool, reach: MarkupPoint) -> MarkupPoint {
        switch tool {
        case .line, .arrow:
            let length = (reach.x * reach.x + reach.y * reach.y).squareRoot()
            guard length > 0 else { return reach }
            let step = Double.pi / 4
            let angle = (atan2(reach.y, reach.x) / step).rounded() * step
            return MarkupPoint(x: cos(angle) * length, y: sin(angle) * length)
        case .rectangle, .oval, .blur, .crop, .magnifier:
            let side = max(abs(reach.x), abs(reach.y))
            return MarkupPoint(x: reach.x < 0 ? -side : side,
                               y: reach.y < 0 ? -side : side)
        default:
            return reach
        }
    }
}
