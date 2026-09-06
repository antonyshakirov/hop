import Foundation

/// What the keep-awake row shows, and when that changes.
/// SPEC: docs/spec.md - "What a running clock costs".
public enum AwakeCountdown {
    /// The figure on the row: whole minutes, rounded up, never below one.
    public static func minutes(remaining: TimeInterval) -> Int {
        max(1, Int((max(0, remaining) / 60).rounded(.up)))
    }

    /// Whether a tick changes anything anyone can see. An endless session shows
    /// `∞` and never changes; a timed one shows minutes, so fifty-nine of every
    /// sixty ticks used to redraw the panel for the same figure.
    public static func publishes(remaining: TimeInterval?, shown: Int?) -> Bool {
        guard let remaining else { return false }
        return minutes(remaining: remaining) != shown
    }
}
