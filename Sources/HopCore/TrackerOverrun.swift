import Foundation

/// Pure decision logic for the panel's 8-hour overrun banner. The banner is a
/// dismissable notice shown ABOVE the space tabs when the tracker's currently
/// open interval has been running for over 8 hours — the same threshold the
/// in-module long-run warning uses, surfaced panel-wide.
///
/// The episode is identified by the OPEN INTERVAL'S START instant: dismissing
/// the banner records that start as "acknowledged", so it stays hidden for the
/// rest of that continuous run. Stopping and starting again yields a new start,
/// so a later 8-hour crossing is a fresh episode the stale acknowledgment can
/// no longer suppress. Stopping the task removes the banner outright (no active
/// start). The acknowledgment is persisted by the view exactly like the other
/// one-time banner dismissals.
public enum TrackerOverrun {
    /// A continuous run counts as overrunning once it exceeds this many seconds.
    public static let threshold: TimeInterval = 8 * 3600

    /// Whether the overrun banner should be visible right now.
    /// - Parameters:
    ///   - activeStart: the start of the currently open interval, or nil if no
    ///     task is running.
    ///   - now: the current instant.
    ///   - acknowledged: the start of the run the user already dismissed the
    ///     banner for, or nil if none has been acknowledged.
    public static func isBannerVisible(activeStart: Date?, now: Date, acknowledged: Date?) -> Bool {
        guard let activeStart else { return false }
        guard now.timeIntervalSince(activeStart) > threshold else { return false }
        if let acknowledged, isSameRun(acknowledged, activeStart) { return false }
        return true
    }

    /// Two run identities match when their start instants coincide. A small
    /// tolerance absorbs the sub-millisecond drift of one side round-tripping
    /// through UserDefaults as a `Double`.
    public static func isSameRun(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSinceReferenceDate - b.timeIntervalSinceReferenceDate) < 0.5
    }
}
