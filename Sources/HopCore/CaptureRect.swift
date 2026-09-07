import Foundation

/// A selection in the screen's points, carrying the display it was drawn on and
/// that display's scale, so the capture can be asked in backing pixels.
/// Tests: Tests/HopCoreTests/CaptureRectTests.swift
public struct CaptureRect: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var scale: Double
    public var displayID: UInt32

    public init(x: Double, y: Double, width: Double, height: Double, scale: Double, displayID: UInt32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.scale = scale
        self.displayID = displayID
    }

    public static func normalized(
        from: MarkupPoint, to: MarkupPoint, scale: Double, displayID: UInt32
    ) -> CaptureRect {
        CaptureRect(x: min(from.x, to.x),
                    y: min(from.y, to.y),
                    width: abs(to.x - from.x),
                    height: abs(to.y - from.y),
                    scale: scale,
                    displayID: displayID)
    }

    public var pixelWidth: Int { Int((width * scale).rounded()) }
    public var pixelHeight: Int { Int((height * scale).rounded()) }

    /// Four pixels a side: anything smaller is a click that slipped.
    public var isUsable: Bool { pixelWidth >= 4 && pixelHeight >= 4 }

    public func clamped(to bounds: CaptureRect) -> CaptureRect {
        let left = max(x, bounds.x)
        let top = max(y, bounds.y)
        let right = min(x + width, bounds.x + bounds.width)
        let bottom = min(y + height, bounds.y + bounds.height)
        return CaptureRect(x: left,
                           y: top,
                           width: max(0, right - left),
                           height: max(0, bottom - top),
                           scale: scale,
                           displayID: displayID)
    }
}
