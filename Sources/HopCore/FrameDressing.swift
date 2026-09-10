import Foundation

/// SPEC: docs/spec.md — "Screenshot".
/// Tests: Tests/HopCoreTests/FrameDressingTests.swift
public struct FrameDressing: Equatable, Codable, Sendable {
    public enum Background: Equatable, Codable, Sendable {
        case preset(Int)
        case colour(String)
        case gradient(String, String)
        /// A file copied into Application Support, and how far to blur it (0...20).
        case picture(String, Int)
    }

    public var isOn: Bool
    public var background: Background
    /// padding, corners and shadow are 0...20, shares of the shorter side.
    public var padding: Int
    public var corners: Int
    public var shadow: Int
    public var browserFrame: Bool
    public var address: String

    public init(
        isOn: Bool, background: Background, padding: Int, corners: Int,
        shadow: Int, browserFrame: Bool, address: String
    ) {
        self.isOn = isOn
        self.background = background
        self.padding = padding
        self.corners = corners
        self.shadow = shadow
        self.browserFrame = browserFrame
        self.address = address
    }

    /// What "reset to defaults" gives back.
    public static let standard = FrameDressing(
        isOn: false, background: .preset(0), padding: 8, corners: 6,
        shadow: 8, browserFrame: false, address: ""
    )

    /// Floor of 34 px: below it the three dots have nowhere to sit.
    public static func barHeight(frame: MarkupPoint) -> Double {
        max(34, frame.y * 0.06)
    }

    public static func inset(frame: MarkupPoint, dressing: FrameDressing) -> Double {
        guard dressing.isOn else { return 0 }
        return min(frame.x, frame.y) * Double(dressing.padding) / 100
    }

    public static func outputSize(frame: MarkupPoint, dressing: FrameDressing) -> MarkupPoint {
        guard dressing.isOn else { return frame }
        let air = inset(frame: frame, dressing: dressing)
        let bar = dressing.browserFrame ? barHeight(frame: frame) : 0
        return MarkupPoint(x: frame.x + air * 2, y: frame.y + air * 2 + bar)
    }

    public static func frameOrigin(frame: MarkupPoint, dressing: FrameDressing) -> MarkupPoint {
        guard dressing.isOn else { return MarkupPoint(x: 0, y: 0) }
        let air = inset(frame: frame, dressing: dressing)
        let bar = dressing.browserFrame ? barHeight(frame: frame) : 0
        return MarkupPoint(x: air, y: air + bar)
    }

    public static func cornerRadius(frame: MarkupPoint, dressing: FrameDressing) -> Double {
        guard dressing.isOn else { return 0 }
        return min(frame.x, frame.y) * Double(dressing.corners) / 200
    }

    public static func shadowRadius(frame: MarkupPoint, dressing: FrameDressing) -> Double {
        guard dressing.isOn else { return 0 }
        return min(frame.x, frame.y) * Double(dressing.shadow) / 150
    }
}
