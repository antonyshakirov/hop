import Foundation

/// Which corner of the menu-bar star a decoration occupies. The colour logic
/// is spatial (Anton's spec): warm dots on top, green time-wedges below, the
/// attention mark top-left, torrent bottom-left.
public enum BadgeCorner: Equatable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Torrent transfer direction, shown in the bottom-left corner.
public enum TorrentArrows: Equatable, Sendable {
    case down, up, both
}

/// The distinct decorations the star can carry, one enum per meaning. Each maps
/// to a FIXED corner and a FIXED monochrome shape (filled vs outline), so the two
/// same-corner pairs — the awake dots (top-right) and the time wedges
/// (bottom-right) — stay distinguishable when colour is off: colour carries the
/// meaning while it is on, the shape carries it while it is off.
public enum IconBadge: Equatable, Sendable, CaseIterable {
    case alert       // top-left: red "!" (white in mono)
    case noSleep     // top-right: yellow dot (filled in both modes)
    case lid         // top-right: orange dot (filled in colour, outline ring in mono)
    case engineTime  // bottom-right: green wedge (filled in both modes) — timer OR stopwatch
    case taskTime    // bottom-right: dark-green wedge (filled in colour, outline in mono) — tracker

    public var corner: BadgeCorner {
        switch self {
        case .alert: return .topLeft
        case .noSleep, .lid: return .topRight
        case .engineTime, .taskTime: return .bottomRight
        }
    }

    /// Monochrome shape: `true` = filled, `false` = outline. The first badge of
    /// each same-corner pair is filled, the second is an outline, so the pair is
    /// still two distinct marks once colour is stripped away.
    public var monoFilled: Bool {
        switch self {
        case .alert, .noSleep, .engineTime: return true
        case .lid, .taskTime: return false
        }
    }
}

/// The fully-resolved set of decorations to draw on the star THIS frame. The
/// blink phase is already applied to `alert`, so the renderer only draws what is
/// present. `torrent` lives in the bottom-left corner and carries its own
/// direction, so it is not part of `IconBadge` (which models the single-mark
/// corners).
public struct IconComposition: Equatable, Sendable {
    public var alert: Bool         // top-left "!" — visible this frame (blink resolved)
    public var noSleep: Bool       // top-right yellow dot
    public var lid: Bool           // top-right orange dot / ring
    public var engineTime: Bool    // bottom-right green wedge (timer or stopwatch)
    public var taskTime: Bool      // bottom-right dark-green wedge (tracker)
    public var torrent: TorrentArrows?  // bottom-left arrows
    public var colored: Bool       // false → monochrome shape mapping

    public init(
        alert: Bool = false, noSleep: Bool = false, lid: Bool = false,
        engineTime: Bool = false, taskTime: Bool = false,
        torrent: TorrentArrows? = nil, colored: Bool = true
    ) {
        self.alert = alert
        self.noSleep = noSleep
        self.lid = lid
        self.engineTime = engineTime
        self.taskTime = taskTime
        self.torrent = torrent
        self.colored = colored
    }

    /// The single-mark badges present, in draw order. Torrent is separate.
    public var badges: [IconBadge] {
        var out: [IconBadge] = []
        if alert { out.append(.alert) }
        if noSleep { out.append(.noSleep) }
        if lid { out.append(.lid) }
        if engineTime { out.append(.engineTime) }
        if taskTime { out.append(.taskTime) }
        return out
    }

    /// Any decoration at all → the plain template fast path can't be used.
    public var isEmpty: Bool {
        !alert && !noSleep && !lid && !engineTime && !taskTime && torrent == nil
    }
}

/// The app state that feeds the icon. Deliberately narrow: the renderer and the
/// controller both talk to the star through this one struct, and every rule
/// below is a pure function of it (fully unit-tested, no AppKit).
public struct IconState: Equatable, Sendable {
    /// The ONE engine slot. A countdown timer and a stopwatch are mutually
    /// exclusive — the engine is only ever one of them — so collapsing both to a
    /// single running/paused/idle value makes the impossible "timer AND stopwatch"
    /// combination unrepresentable, and the star never has to tell the two apart
    /// (the title already shows whether the value falls or climbs).
    public enum Engine: Equatable, Sendable { case idle, running, paused }

    public var engine: Engine
    /// The engine's own value is already spelled out as digits in the menu-bar
    /// title (countdown on) — the wedge would just duplicate it, so it is dropped.
    public var engineTimeInTitle: Bool
    /// A task is tracking (its open interval is running).
    public var tracking: Bool
    /// The task's `today` value is already shown as digits in the title
    /// (`trackerTimeInBar` on and the title not claimed by the countdown).
    public var taskTimeInTitle: Bool
    public var noSleep: Bool     // keep-awake active
    public var lid: Bool         // lid mode applied
    /// Steady attention source (monitor red zone): the "!" burns without blinking.
    public var alertSteady: Bool
    /// Blinking attention source (a task running past 8h): the "!" blinks.
    public var alertBlinking: Bool
    /// The current tick's blink phase (`true` = lit). Only the blinking source
    /// obeys it; a steady source is lit regardless.
    public var blinkOn: Bool
    public var torrentDown: Bool
    public var torrentUp: Bool
    public var colored: Bool

    public init(
        engine: Engine = .idle, engineTimeInTitle: Bool = false,
        tracking: Bool = false, taskTimeInTitle: Bool = false,
        noSleep: Bool = false, lid: Bool = false,
        alertSteady: Bool = false, alertBlinking: Bool = false, blinkOn: Bool = true,
        torrentDown: Bool = false, torrentUp: Bool = false, colored: Bool = true
    ) {
        self.engine = engine
        self.engineTimeInTitle = engineTimeInTitle
        self.tracking = tracking
        self.taskTimeInTitle = taskTimeInTitle
        self.noSleep = noSleep
        self.lid = lid
        self.alertSteady = alertSteady
        self.alertBlinking = alertBlinking
        self.blinkOn = blinkOn
        self.torrentDown = torrentDown
        self.torrentUp = torrentUp
        self.colored = colored
    }
}

/// Pure composition matrix: app state → the badges to draw. No AppKit, fully
/// testable; the renderer (`MenuBarIcon.compose`) draws whatever this returns.
public enum IconBadges {
    public static func compose(_ s: IconState) -> IconComposition {
        // Time wedges appear only while their clock is actually RUNNING (a play
        // triangle means "running", so a paused engine shows none) and only when
        // that clock's value isn't already spelled out as digits in the title —
        // the digits are the wedge's redundant twin, so the two never co-exist.
        let engineTime = s.engine == .running && !s.engineTimeInTitle
        let taskTime = s.tracking && !s.taskTimeInTitle

        // Both attention sources light the SAME top-left "!". A steady source
        // (monitor) is always lit; a blinking source (8h task) shows only on the
        // lit phase. If both are active the steady one keeps it lit throughout.
        let alert = s.alertSteady || (s.alertBlinking && s.blinkOn)

        let torrent: TorrentArrows?
        switch (s.torrentDown, s.torrentUp) {
        case (true, true): torrent = .both
        case (true, false): torrent = .down
        case (false, true): torrent = .up
        case (false, false): torrent = nil
        }

        return IconComposition(
            alert: alert, noSleep: s.noSleep, lid: s.lid,
            engineTime: engineTime, taskTime: taskTime,
            torrent: torrent, colored: s.colored
        )
    }
}
