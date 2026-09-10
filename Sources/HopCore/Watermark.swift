import Foundation

/// A mark stamped over the exported picture: the user's own text, or an image
/// copied into Hop's support folder so a file moved later cannot empty it.
/// SPEC: docs/spec.md — "Screenshot".
/// Tests: Tests/HopCoreTests/WatermarkTests.swift
public struct Watermark: Equatable, Codable, Sendable {
    public enum Spot: String, Codable, CaseIterable, Sendable {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
        case centre
    }

    public var isOn: Bool
    public var text: String
    /// The copy's file name inside Application Support, never the original path.
    public var imageName: String?
    /// 5...100 per cent.
    public var opacity: Int
    /// 1...20, a share of the frame's shorter side.
    public var size: Int
    public var spot: Spot
    public var tiled: Bool
    /// Air between tiles, 10...300 per cent of the mark's own size. Size and
    /// count are separate wishes: a big mark repeated rarely is a real one.
    public var spread: Int
    /// -45, 0 or 45 degrees.
    public var slant: Int

    public init(
        isOn: Bool, text: String, imageName: String?, opacity: Int,
        size: Int, spot: Spot, tiled: Bool, spread: Int = 80, slant: Int = 0
    ) {
        self.isOn = isOn
        self.text = text
        self.imageName = imageName
        self.opacity = opacity
        self.size = size
        self.spot = spot
        self.tiled = tiled
        self.spread = spread
        self.slant = slant
    }

    /// Top right by default: the bottom of the editor is where the toolbar
    /// floats, and a mark under it cannot be seen at all.
    public static let standard = Watermark(
        isOn: false, text: "", imageName: nil, opacity: 40,
        size: 5, spot: .topTrailing, tiled: false, spread: 80, slant: 0
    )

    public var hasSomethingToStamp: Bool {
        guard isOn else { return false }
        if let name = imageName, !name.isEmpty { return true }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func height(in frame: MarkupPoint, watermark: Watermark) -> Double {
        min(frame.x, frame.y) * Double(watermark.size) / 100
    }

    public static func origin(
        of mark: MarkupPoint, in frame: MarkupPoint, spot: Spot, inset: Double
    ) -> MarkupPoint {
        switch spot {
        case .topLeading:
            return MarkupPoint(x: inset, y: inset)
        case .topTrailing:
            return MarkupPoint(x: frame.x - mark.x - inset, y: inset)
        case .bottomLeading:
            return MarkupPoint(x: inset, y: frame.y - mark.y - inset)
        case .bottomTrailing:
            return MarkupPoint(x: frame.x - mark.x - inset, y: frame.y - mark.y - inset)
        case .centre:
            return MarkupPoint(x: (frame.x - mark.x) / 2, y: (frame.y - mark.y) / 2)
        }
    }

    public static func tileStep(of mark: MarkupPoint, spread: Int) -> MarkupPoint {
        let air = 1 + Double(max(10, min(300, spread))) / 100
        return MarkupPoint(x: mark.x * air, y: mark.y * air)
    }
}
