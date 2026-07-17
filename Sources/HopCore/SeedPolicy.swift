public enum SeedPolicy {
    /// Stop seeding once we've given back as much as we took — but only if the
    /// user opted in, and never before the download itself is complete.
    public static func shouldPause(stats: TorrentStats, stopAtRatio1: Bool) -> Bool {
        stopAtRatio1 && stats.finished && stats.ratio >= 1.0
    }
}
