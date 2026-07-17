import Foundation

/// Lifecycle state of a torrent as reported by the engine (rqbit).
public enum TorrentState: String, Codable {
    case initializing, live, paused, error
}

/// A single file inside a torrent's payload, with its own selection flag
/// (users can opt out of downloading files they don't want).
public struct TorrentFile: Equatable {
    public let index: Int
    public let name: String
    public let lengthBytes: Int64
    public var selected: Bool

    public init(index: Int, name: String, lengthBytes: Int64, selected: Bool) {
        self.index = index
        self.name = name
        self.lengthBytes = lengthBytes
        self.selected = selected
    }
}

/// A snapshot of a torrent's live progress and transfer numbers. Pure data —
/// the engine polls rqbit and decodes its JSON into this shape.
public struct TorrentStats: Equatable {
    public let state: TorrentState
    public let progressBytes: Int64
    public let totalBytes: Int64
    public let uploadedBytes: Int64
    public let downloadBps: Int64
    public let uploadBps: Int64
    public let peersLive: Int
    public let peersSeen: Int
    public let etaSeconds: Int?
    public let finished: Bool
    public let fileProgressBytes: [Int64]

    public init(
        state: TorrentState,
        progressBytes: Int64,
        totalBytes: Int64,
        uploadedBytes: Int64,
        downloadBps: Int64,
        uploadBps: Int64,
        peersLive: Int,
        peersSeen: Int,
        etaSeconds: Int?,
        finished: Bool,
        fileProgressBytes: [Int64]
    ) {
        self.state = state
        self.progressBytes = progressBytes
        self.totalBytes = totalBytes
        self.uploadedBytes = uploadedBytes
        self.downloadBps = downloadBps
        self.uploadBps = uploadBps
        self.peersLive = peersLive
        self.peersSeen = peersSeen
        self.etaSeconds = etaSeconds
        self.finished = finished
        self.fileProgressBytes = fileProgressBytes
    }

    /// Download progress as a 0...1 fraction; 0 while the total size is
    /// still unknown (e.g. during metadata fetch) rather than dividing by zero.
    public var fraction: Double {
        totalBytes > 0 ? min(1, max(0, Double(progressBytes) / Double(totalBytes))) : 0
    }

    /// Upload-to-download ratio. Uses bytes downloaded so far (not the
    /// torrent's total size) as the denominator, matching how seed ratio
    /// is conventionally reported while a download is still in progress.
    public var ratio: Double {
        progressBytes > 0 ? Double(uploadedBytes) / Double(progressBytes) : 0
    }
}

/// A torrent tracked by the app. `id` is rqbit's per-session integer (kept
/// as a String); `infoHash` is the stable hex identifier used for
/// persistence and dedup across sessions.
public struct Torrent: Equatable, Identifiable {
    public let id: String
    public let infoHash: String
    public let name: String
    public let files: [TorrentFile]
    public let outputFolder: String
    public var stats: TorrentStats?

    public init(
        id: String,
        infoHash: String,
        name: String,
        files: [TorrentFile],
        outputFolder: String,
        stats: TorrentStats?
    ) {
        self.id = id
        self.infoHash = infoHash
        self.name = name
        self.files = files
        self.outputFolder = outputFolder
        self.stats = stats
    }
}
