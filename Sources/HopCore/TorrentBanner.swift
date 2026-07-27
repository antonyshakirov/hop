/// What a torrent's banner says. A finished torrent used to post a banner with
/// its own title and NO body, and the notification helper filled the gap with
/// its default — the timer's "the timer has finished" (Anton, 2026-07-26). The
/// message is a value here so that no banner can inherit another module's words
/// again: there is nothing to leave unset.
public enum TorrentBanner: Equatable {
    /// The payload is complete and the torrent keeps sharing it.
    case downloadedSeeding(bytes: Int64)
    /// Complete, and nothing is being shared: the torrent is not live.
    case downloaded(bytes: Int64)
    /// Sharing stopped because the give-back target was reached.
    case seedingFinished(uploadedBytes: Int64)

    /// The banner a torrent earns the moment its download completes.
    ///
    /// The size quoted is what actually landed on disk (`progressBytes`), not
    /// the torrent's nominal total: with only some files selected those two
    /// differ, and the number in the banner has to be the one the user can find
    /// in Finder.
    public static func finished(stats: TorrentStats, seeding: Bool) -> TorrentBanner {
        seeding
            ? .downloadedSeeding(bytes: stats.progressBytes)
            : .downloaded(bytes: stats.progressBytes)
    }

    /// The banner for the moment the seeding policy stops a completed torrent.
    public static func seedingStopped(stats: TorrentStats) -> TorrentBanner {
        .seedingFinished(uploadedBytes: stats.uploadedBytes)
    }

    /// The byte count the message quotes — downloaded or given back.
    public var bytes: Int64 {
        switch self {
        case let .downloadedSeeding(bytes), let .downloaded(bytes):
            return bytes
        case let .seedingFinished(uploadedBytes):
            return uploadedBytes
        }
    }
}
