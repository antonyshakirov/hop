import Foundation

/// SPEC: docs/spec.md — each monitor keeps its own marks.
/// Tests: Tests/HopCoreTests/MarkupScreensTests.swift
public enum MarkupScreens {
    public static func belongs(_ shape: MarkupShape, to display: UInt32?) -> Bool {
        display == nil || shape.display == nil || shape.display == display
    }

    public static func on(_ display: UInt32?, _ shapes: [MarkupShape]) -> [MarkupShape] {
        shapes.filter { belongs($0, to: display) }
    }
}
