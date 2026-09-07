import Foundation

/// Ink that goes on its own. The view asks for an opacity instead of owning a
/// timer per stroke, and asks whether anything is still fading at all — a layer
/// of ordinary marks must keep no schedule running.
/// Tests: Tests/HopCoreTests/FadingInkTests.swift
public enum FadingInk {
    /// Seconds at full strength after the pointer lifts.
    public static let life: TimeInterval = 2
    /// Seconds it takes to go from full strength to nothing.
    public static let fade: TimeInterval = 0.5

    public static func opacity(of shape: MarkupShape, now: TimeInterval) -> Double {
        guard shape.tool == .fadingInk else { return 1 }
        let age = now - shape.createdAt
        if age <= life { return 1 }
        if age >= life + fade { return 0 }
        return 1 - (age - life) / fade
    }

    public static func alive(_ shapes: [MarkupShape], now: TimeInterval) -> [MarkupShape] {
        shapes.filter { opacity(of: $0, now: now) > 0 }
    }

    public static func needsTicking(_ shapes: [MarkupShape], now: TimeInterval) -> Bool {
        shapes.contains { $0.tool == .fadingInk && opacity(of: $0, now: now) > 0 }
    }
}
