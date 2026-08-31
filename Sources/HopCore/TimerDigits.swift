import Foundation

/// Which digit group of the timer display a point falls in, and which characters
/// of `HH:MM:SS` that group covers.
public enum TimerDigits {
    public static let hours: TimeInterval = 3600
    public static let minutes: TimeInterval = 60
    public static let seconds: TimeInterval = 1

    /// The group at a point given as a fraction of the display's width.
    /// `hoursHidden` is the "units" style under an hour, where the display holds
    /// two groups instead of three and splits down the middle.
    public static func unit(atFraction fraction: Double, hoursHidden: Bool) -> TimeInterval {
        if hoursHidden { return fraction < 0.5 ? minutes : seconds }
        return fraction < 0.31 ? hours : (fraction < 0.65 ? minutes : seconds)
    }

    /// → the characters the group occupies in `HH:MM:SS`, colons excluded.
    public static func range(for unit: TimeInterval) -> Range<Int> {
        switch unit {
        case hours: return 0..<2
        case minutes: return 3..<5
        default: return 6..<8
        }
    }
}
