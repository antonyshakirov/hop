import Foundation

/// Numbers in the step circles: they follow the order the circles were placed,
/// so dragging one keeps its number and deleting one closes the gap.
/// Tests: Tests/HopCoreTests/StepNumberingTests.swift
public enum StepNumbering {
    public static func next(in shapes: [MarkupShape]) -> Int {
        (shapes.compactMap(\.step).max() ?? 0) + 1
    }

    public static func renumbered(_ shapes: [MarkupShape]) -> [MarkupShape] {
        let placed = shapes.enumerated()
            .filter { $0.element.tool == .steps }
            .sorted { $0.element.createdAt < $1.element.createdAt }
        guard !placed.isEmpty else { return shapes }

        var numbers: [Int: Int] = [:]
        var counted: [UInt32?: Int] = [:]
        for item in placed {
            counted[item.element.display, default: 0] += 1
            numbers[item.offset] = counted[item.element.display]
        }

        return shapes.enumerated().map { index, shape in
            guard let number = numbers[index] else { return shape }
            var renumbered = shape
            renumbered.step = number
            return renumbered
        }
    }
}
