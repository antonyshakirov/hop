import Foundation

/// SPEC: docs/spec.md "Torrent engine: version floor and stall recovery". Tests: TorrentStallWatchTests.
public struct TorrentStallWatch {
    public static let stallAfter: TimeInterval = 180
    public static let spacing: TimeInterval = 600
    public static let maxFruitlessRestarts = 3

    public struct Signal: Equatable {
        public let stalled: Bool
        public let flowing: Bool
        public let checking: Bool
        public init(stalled: Bool, flowing: Bool, checking: Bool) {
            self.stalled = stalled; self.flowing = flowing; self.checking = checking
        }
    }

    private var stalledSince: Date?
    private var lastRestart: Date?
    private var fruitlessRestarts = 0
    private var online = true
    private var lastInterfaces: [String]?

    public init() {}

    public static func assess(_ rows: [(stats: TorrentStats?, paused: Bool)]) -> Signal {
        var stalled = false, flowing = false, checking = false
        for row in rows where !row.paused {
            guard let s = row.stats else { continue }
            if s.state == .initializing { checking = true; continue }
            guard s.state == .live else { continue }
            if s.peersLive > 0 || s.downloadBps > 0 || s.uploadBps > 0 {
                flowing = true
            } else if !s.finished {
                stalled = true
            }
        }
        return Signal(stalled: stalled, flowing: flowing, checking: checking)
    }

    /// Feeds one poll. Returns true when the engine should be restarted now.
    public mutating func observe(_ signal: Signal, now: Date) -> Bool {
        if signal.flowing { fruitlessRestarts = 0 }
        guard signal.stalled, !signal.flowing, !signal.checking, online else {
            stalledSince = nil
            return false
        }
        guard let since = stalledSince else { stalledSince = now; return false }
        guard now.timeIntervalSince(since) >= Self.stallAfter,
              fruitlessRestarts < Self.maxFruitlessRestarts else { return false }
        if let last = lastRestart, now.timeIntervalSince(last) < Self.spacing { return false }
        lastRestart = now
        stalledSince = nil
        fruitlessRestarts += 1
        return true
    }

    /// The engine did not come back up, so the attempt says nothing about the swarm.
    public mutating func restartFailed() {
        fruitlessRestarts = max(0, fruitlessRestarts - 1)
    }

    /// Feeds an `NWPathMonitor` update. Coming online or a different set of
    /// interfaces re-arms the watch; the first update only records the path.
    public mutating func pathUpdated(online isOnline: Bool, interfaces: [String]) {
        let current = interfaces.sorted()
        defer { online = isOnline; lastInterfaces = isOnline ? current : [] }
        guard isOnline else { stalledSince = nil; return }
        guard let previous = lastInterfaces else { return }
        if !online || previous != current { fruitlessRestarts = 0 }
    }
}
