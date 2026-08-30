import Foundation

/// How often the VPN module looks, and whether this look re-reads the system's
/// list.
///
/// Until 2026-08-30 the list was re-read every 30 seconds with the panel closed,
/// so a tunnel that came up outside Hop took up to half a minute to reach the
/// menu-bar dot, and one that went down took the same whenever its `utun` stayed
/// standing behind it (Anton, 2026-08-30). The system announces both the moment
/// they happen; this decides what the module does about an announcement.
///
/// Nothing here talks to the system. It is given the state and returns a plan,
/// which is what makes every rule below testable.
public struct VPNWatchCadence: Equatable, Sendable {

    /// How long an announcement keeps the module looking quickly. A tunnel does
    /// not arrive with the signal that precedes it: the route change is published
    /// first and the session then walks `Connecting → Connected` over the next
    /// few seconds, so a single reading at the moment of the signal would catch
    /// the transition rather than its outcome. This window is also what covers
    /// the clients whose own state never lands under a key worth watching — the
    /// signal that reaches us is some neighbouring change, and the window reads
    /// until the truth shows up.
    public static let burst: TimeInterval = 8
    /// The cadence during that window.
    public static let burstInterval: TimeInterval = 1
    /// The cadence with the panel open or any tunnel up. Counters cost
    /// microseconds, so this is set by how quickly a stalled tunnel should show.
    public static let watchInterval: TimeInterval = 2
    /// The cadence with nothing connected and nothing on screen. It still has to
    /// tick: it is the floor under the announcements, so a client the system
    /// never announces at all degrades to the old behaviour instead of to none.
    public static let idleInterval: TimeInterval = 30
    /// How close behind the last reading an announcement may arrive and still
    /// ride on it. A tunnel coming up moves several keys at once and each arrives
    /// as its own callback; one reading answers all of them, and the window above
    /// catches whatever settles after.
    public static let coalesce: TimeInterval = 0.3

    /// How long until the next look.
    public let interval: TimeInterval
    /// Whether this look re-reads `scutil --nc list`, which costs a process.
    public let readsList: Bool

    /// The plan for a look taken now.
    ///
    /// - `tracking`: any tunnel currently being measured.
    /// - `vanished`: a tracked interface has gone from `getifaddrs`, which is free
    ///   to learn and means the list is already known to be out of date.
    /// - `lastChange`: when the system last announced a network change.
    public static func decide(panelOpen: Bool, tracking: Bool, vanished: Bool,
                              lastChange: Date?, lastListRead: Date,
                              now: Date) -> VPNWatchCadence {
        let bursting = lastChange.map { now.timeIntervalSince($0) < burst } ?? false
        let interval = bursting
            ? burstInterval
            : ((panelOpen || tracking) ? watchInterval : idleInterval)
        let readsList = panelOpen || bursting || vanished
            || now.timeIntervalSince(lastListRead) >= idleInterval
        return VPNWatchCadence(interval: interval, readsList: readsList)
    }

    /// Whether an announcement arriving now earns its own reading, or is close
    /// enough behind the last one to be answered by it.
    public static func worthReading(lastListRead: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastListRead) >= coalesce
    }
}
