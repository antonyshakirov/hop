import Foundation

/// Tracks when the user last actively touched Hop — opened the panel, fired a
/// hotkey, ran a conversion, opened a window. The updater treats a long enough
/// quiet gap since then as "not in use right now" and installs at that moment.
public final class ActivityTracker {
    private var lastInteraction: Date

    /// Starts idle on purpose: a freshly launched app the user isn't touching is
    /// a fine moment to update, matching the check that already runs shortly
    /// after launch. Real interactions move the stamp forward from there.
    public init(lastInteraction: Date = .distantPast) {
        self.lastInteraction = lastInteraction
    }

    public func note(at date: Date = Date()) {
        // never move the stamp backwards — an out-of-order event must not make
        // the app look "more recently used" than it actually was
        if date > lastInteraction { lastInteraction = date }
    }

    public func secondsSinceInteraction(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(lastInteraction)
    }
}

/// Decides whether a found release may install right now. Pure and clock-free so
/// the whole truth table is unit-tested without AppKit or a real timer.
public enum UpdateInstallPolicy {
    /// Quiet time with no interaction before the app counts as "not in use".
    public static let idleThreshold: TimeInterval = 20 * 60

    /// - Parameters:
    ///   - critical: a crash/security release (from the manifest's `critical`).
    ///   - timerBusy: a timer is set — running or paused (never idle/finished).
    ///   - keepAwakeActive: sleep prevention is on.
    ///   - panelOpen: the menu-bar panel popover is showing right now.
    ///   - converterBusy: a file conversion is in progress right now.
    ///   - secondsSinceInteraction: age of the last user interaction.
    public static func canInstall(
        critical: Bool,
        timerBusy: Bool,
        keepAwakeActive: Bool,
        panelOpen: Bool,
        converterBusy: Bool,
        secondsSinceInteraction: TimeInterval,
        idleThreshold: TimeInterval = idleThreshold
    ) -> Bool {
        // A set or running timer is sacred: never relaunch out from under it,
        // not even for a critical release.
        if timerBusy { return false }
        // Crash/security fixes shouldn't wait for a quiet gap. They still yield
        // to a running timer above and install at the first moment without one.
        if critical { return true }
        // The user is deliberately keeping the Mac awake (a talk, a long
        // download) — don't disrupt that with a relaunch.
        if keepAwakeActive { return false }
        // In active use this very second.
        if panelOpen || converterBusy { return false }
        // Otherwise install only after a long enough quiet gap.
        return secondsSinceInteraction >= idleThreshold
    }
}
