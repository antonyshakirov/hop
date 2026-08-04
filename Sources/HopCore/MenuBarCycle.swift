import Foundation

/// Sharing the menu bar's one line of digits between several running clocks.
///
/// A timer and a tracked task can run at the same time, and the bar has room
/// for one figure. Rather than ranking them once and hiding the loser, the bar
/// takes turns: each reading holds the line for a few seconds, hands it over
/// through a fade, and comes back. A small glyph in front of the digits says
/// which clock is speaking, because a number alone is ambiguous.
///
/// The turn is a function of the clock, not of stored state: every redraw
/// computes it from the current time, so a redraw that arrives late or twice
/// cannot desynchronise the rotation.
public enum MenuBarCycle {
    /// How long one reading holds the line.
    public static let interval: TimeInterval = 5

    /// How long a handover takes, start to finish. The digits are at zero
    /// opacity exactly on the boundary, so the reading that leaves and the one
    /// that arrives are never both legible.
    public static let fade: TimeInterval = 0.5

    /// Which of `count` readings holds the line at `now`.
    public static func index(count: Int, now: Date, interval: TimeInterval = interval) -> Int {
        guard count > 1 else { return 0 }
        let turns = (now.timeIntervalSinceReferenceDate / interval).rounded(.down)
        // negative dates are not a real case, but a negative modulo would be a
        // crash rather than a wrong number, so it is folded back here
        let position = Int(turns.truncatingRemainder(dividingBy: Double(count)))
        return position < 0 ? position + count : position
    }

    /// Opacity of the digits at `now`, 0...1: full through the middle of a turn,
    /// dipping to zero across the boundary between turns.
    ///
    /// The curve is eased at both ends rather than linear. A linear fade has a
    /// corner where it meets full opacity, and the eye reads that corner as a
    /// flicker — the label looked like it blinked rather than dissolved.
    public static func opacity(
        now: Date, interval: TimeInterval = interval, fade: TimeInterval = fade
    ) -> Double {
        guard interval > 0, fade > 0 else { return 1 }
        let elapsed = now.timeIntervalSinceReferenceDate
        let intoTurn = elapsed - (elapsed / interval).rounded(.down) * interval
        let toBoundary = min(intoTurn, interval - intoTurn)
        let linear = min(1, toBoundary / (fade / 2))
        return linear * linear * (3 - 2 * linear)
    }

    /// Seconds until the next handover begins. The bar redraws once a second on
    /// the heartbeat, which is far too coarse for a fade, so it uses this to
    /// spin up a brief finer tick and let it die again — an app that lives in
    /// the menu bar has no business waking up twenty times a second all day.
    public static func untilFade(
        now: Date, interval: TimeInterval = interval, fade: TimeInterval = fade
    ) -> TimeInterval {
        guard interval > 0 else { return .greatestFiniteMagnitude }
        let elapsed = now.timeIntervalSinceReferenceDate
        let intoTurn = elapsed - (elapsed / interval).rounded(.down) * interval
        // still climbing back out of the last handover — the fine tick is
        // needed NOW, not in a few seconds
        if intoTurn < fade / 2 { return 0 }
        return max(0, interval - fade / 2 - intoTurn)
    }
}
