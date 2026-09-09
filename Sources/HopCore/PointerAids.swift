import Foundation

/// What the presenting pointer adds to the screen, and how strong it is.
/// Tests: Tests/HopCoreTests/PointerAidsTests.swift
public struct PointerAids: Equatable, Codable, Sendable {
    public var ring: Bool
    public var spotlight: Bool
    public var trail: Bool
    public var clicks: Bool
    /// "#RRGGBB" for every mark it draws.
    public var hex: String
    /// The ring's radius in points; the spotlight is three times it.
    public var size: Double

    public static let standard = PointerAids(ring: true, spotlight: false, trail: false,
                                             clicks: true, hex: "#FFD60A", size: 26)

    public init(ring: Bool, spotlight: Bool, trail: Bool, clicks: Bool,
                hex: String, size: Double) {
        self.ring = ring
        self.spotlight = spotlight
        self.trail = trail
        self.clicks = clicks
        self.hex = hex
        self.size = size
    }

    /// Nothing drawn means nothing watched.
    public var isOn: Bool { ring || spotlight || trail || clicks }

    public static let trailLife: TimeInterval = 0.55
    public static let clickLife: TimeInterval = 0.45

    /// 1 at birth, 0 once it is gone.
    public static func fade(age: TimeInterval, life: TimeInterval) -> Double {
        guard life > 0 else { return 0 }
        return max(0, min(1, 1 - age / life))
    }

    public static func clickRadius(age: TimeInterval, from base: Double) -> Double {
        base * (1 + 1.6 * min(1, max(0, age / clickLife)))
    }
}
