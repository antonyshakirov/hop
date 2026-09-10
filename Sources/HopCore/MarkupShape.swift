import Foundation

/// SPEC: .claude/specs/2026-09-07-markup-modules-design.md
public enum MarkupTool: String, Codable, CaseIterable, Sendable {
    /// Not a mark of its own: the one that picks up the marks already made.
    case select
    case pencil
    case fadingInk
    case marker
    case arrow
    case line
    case rectangle
    case oval
    case steps
    case text
    case blur
    case magnifier
    case eraser
    case crop
}

/// Pixels of the captured frame, or points of the screen the layer covers.
public struct MarkupPoint: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Every tool carries its own pair; switching tools resets neither.
public struct MarkupInk: Equatable, Codable, Sendable {
    public var hex: String
    public var width: Double

    public init(hex: String, width: Double) {
        self.hex = hex
        self.width = width
    }
}

public struct MarkupBlur: Equatable, Codable, Sendable {
    /// `inside` hides what the region covers; `around` keeps it sharp.
    public enum Mode: String, Codable, Sendable {
        case inside
        case around
    }

    public enum Shape: String, Codable, Sendable {
        case rectangle
        case oval
        case lasso
    }

    public enum Style: String, Codable, Sendable {
        case blur
        case pixels
    }

    public var mode: Mode
    public var shape: Shape
    public var style: Style
    /// 1...10, mapped to a radius by the renderer.
    public var strength: Int
    /// 0...10, `around` only.
    public var dim: Int

    /// SPEC: docs/spec.md — "Blur works in both directions", the dimming slider.
    public var offersDim: Bool { mode == .around }

    /// How far the gaussian reaches, in the picture's own points. The scale is
    /// deliberately NOT straight: on a straight one the lightest setting was
    /// already too much to read through, and everything past the middle looked
    /// the same. SPEC: docs/spec.md
    /// Tests: Tests/HopCoreTests/MarkupBlurTests.swift
    public static func radius(forStrength strength: Int) -> Double {
        let share = Double(min(max(strength, 1), 10) - 1) / 9
        return 0.5 + pow(share, 1.7) * 14.5
    }

    /// The side of a mosaic tile, in the picture's own points.
    public static func mosaic(forStrength strength: Int) -> Double {
        let share = Double(min(max(strength, 1), 10) - 1) / 9
        return 3 + pow(share, 1.7) * 31
    }

    public init(mode: Mode, shape: Shape, style: Style, strength: Int, dim: Int) {
        self.mode = mode
        self.shape = shape
        self.style = style
        self.strength = strength
        self.dim = dim
    }
}

public struct MarkupShape: Equatable, Codable, Identifiable, Sendable {
    public let id: UUID
    public var tool: MarkupTool
    /// What the tool needs: two corners, a whole stroke, or one centre.
    public var points: [MarkupPoint]
    public var ink: MarkupInk
    public var text: String?
    public var step: Int?
    public var blur: MarkupBlur?
    /// The head an arrow was drawn with; nil for every other tool.
    public var arrow: ArrowStyle?
    /// How much the loupe magnifies; nil for every other tool, and for lenses
    /// placed before the dial existed.
    public var magnification: Double?
    /// The monitor a drawing-layer mark was made on; nil in the editor, where there is one picture.
    public var display: UInt32?
    /// Seconds since the surface opened; fading ink and step order read it.
    public var createdAt: TimeInterval

    public init(
        id: UUID = UUID(),
        tool: MarkupTool,
        points: [MarkupPoint],
        ink: MarkupInk,
        text: String? = nil,
        step: Int? = nil,
        blur: MarkupBlur? = nil,
        arrow: ArrowStyle? = nil,
        magnification: Double? = nil,
        display: UInt32? = nil,
        createdAt: TimeInterval
    ) {
        self.id = id
        self.tool = tool
        self.points = points
        self.ink = ink
        self.text = text
        self.step = step
        self.blur = blur
        self.arrow = arrow
        self.magnification = magnification
        self.display = display
        self.createdAt = createdAt
    }
}
