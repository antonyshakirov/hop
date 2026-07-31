import Foundation

/// Whether a tunnel the system calls connected is actually carrying anything.
///
/// `scutil` reports the state of the SESSION, not of the traffic. A tunnel whose
/// server has gone quiet stays `Connected` while nothing comes back through it —
/// the switch is green and the internet is dead (Anton, 2026-07-31). The only
/// local evidence that tells the two apart is the tunnel interface's own
/// counters: packets keep going out and none come in.
///
/// Nothing here talks to the system. It is fed readings and returns a verdict,
/// which is what makes every rule below testable.
public struct TunnelLiveness: Equatable, Sendable {

    /// One reading of an interface's packet counters.
    public struct Sample: Equatable, Sendable {
        public let inPackets: UInt64
        public let outPackets: UInt64
        public let at: Date

        public init(inPackets: UInt64, outPackets: UInt64, at: Date) {
            self.inPackets = inPackets
            self.outPackets = outPackets
            self.at = at
        }
    }

    /// How long the tunnel may bring nothing back before it is called stalled.
    /// Long enough that a connection which drops and returns — which is how a
    /// flaky link behaves all day — never reaches the verdict.
    public static let silence: TimeInterval = 6

    /// How many packets have to go out during that silence for the silence to
    /// mean anything. Without this floor a Mac left alone at night, where nothing
    /// is asking for anything, would read exactly like a dead tunnel. With it, the
    /// verdict only ever appears when something wanted an answer and did not get
    /// one — which is the only moment it matters. Three rather than one, so a
    /// single stray packet cannot accuse a tunnel on its own.
    public static let demand: UInt64 = 3

    private var previous: Sample?
    private var arrivedAt: Date?
    private var sentSinceArrival: UInt64 = 0

    /// The verdict as of the last reading: the tunnel is up and nothing is
    /// getting through it.
    public private(set) var isStalled = false

    public init() {}

    /// Takes one reading and returns the verdict.
    ///
    /// Deliberately asymmetric — slow to accuse, instant to forgive. A single
    /// returning packet clears the accusation on the sample that carries it, while
    /// making the accusation takes `silence` seconds of one-sided traffic. The
    /// other way round the icon would flicker between two colours every time a
    /// connection wobbled.
    @discardableResult
    public mutating func observe(_ sample: Sample) -> Bool {
        guard let last = previous else {
            // the first reading is a baseline, not evidence
            restart(at: sample)
            return false
        }
        // A counter that goes backwards is an interface replaced under the same
        // name, or the 32-bit value wrapping. Neither says anything about the
        // tunnel, so it re-baselines instead of accusing.
        guard sample.inPackets >= last.inPackets, sample.outPackets >= last.outPackets else {
            restart(at: sample)
            return false
        }
        previous = sample
        if sample.inPackets > last.inPackets {
            arrivedAt = sample.at
            sentSinceArrival = 0
            isStalled = false
            return false
        }
        sentSinceArrival += sample.outPackets - last.outPackets
        let quiet = sample.at.timeIntervalSince(arrivedAt ?? sample.at)
        isStalled = quiet >= Self.silence && sentSinceArrival >= Self.demand
        return isStalled
    }

    private mutating func restart(at sample: Sample) {
        previous = sample
        arrivedAt = sample.at
        sentSinceArrival = 0
        isStalled = false
    }
}
