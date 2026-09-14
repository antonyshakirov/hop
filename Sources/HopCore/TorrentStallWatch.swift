import Foundation

/// SPEC: docs/spec.md "Torrent engine: version floor and stall recovery". Tests: TorrentStallWatchTests.
public struct TorrentStallWatch {
    public static let stallAfter: TimeInterval = 180
    public static let spacing: TimeInterval = 600
    public static let maxFruitlessRestarts = 3

    private var stalledSince: Date?
    private var lastRestart: Date?
    private var fruitlessRestarts = 0

    public init() {}

    public static func assess(_ rows: [(stats: TorrentStats?, paused: Bool)]) -> (stalled: Bool, flowing: Bool) {
        var stalled = false
        var flowing = false
        for row in rows where !row.paused {
            guard let s = row.stats, s.state == .live else { continue }
            if s.peersLive > 0 || s.downloadBps > 0 || s.uploadBps > 0 {
                flowing = true
            } else if !s.finished {
                stalled = true
            }
        }
        return (stalled, flowing)
    }

    /// Feeds one poll. Returns true when the engine should be restarted now.
    public mutating func observe(stalled: Bool, flowing: Bool, now: Date) -> Bool {
        if flowing {
            fruitlessRestarts = 0
            stalledSince = nil
            return false
        }
        guard stalled else { stalledSince = nil; return false }
        guard let since = stalledSince else { stalledSince = now; return false }
        guard now.timeIntervalSince(since) >= Self.stallAfter,
              fruitlessRestarts < Self.maxFruitlessRestarts else { return false }
        if let last = lastRestart, now.timeIntervalSince(last) < Self.spacing { return false }
        lastRestart = now
        stalledSince = nil
        fruitlessRestarts += 1
        return true
    }

    public mutating func networkChanged() {
        fruitlessRestarts = 0
    }
}
