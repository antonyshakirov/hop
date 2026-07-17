import Foundation

/// Decoders for rqbit's HTTP API JSON into HopCore's pure types.
/// Field names mirror rqbit v8.1.1 responses (see Tests/.../Fixtures).
public enum RqbitDecoding {
    public static func stats(from data: Data) throws -> TorrentStats {
        let raw = try JSONDecoder().decode(RawStats.self, from: data)
        let state = TorrentState(rawValue: raw.state) ?? .initializing
        let live = raw.live
        let bytesPerSec: (Double?) -> Int64 = { mbps in
            guard let mbps else { return 0 }
            return Int64((mbps * 1_048_576).rounded())
        }
        return TorrentStats(
            state: state,
            progressBytes: raw.progress_bytes,
            totalBytes: raw.total_bytes,
            uploadedBytes: raw.uploaded_bytes,
            downloadBps: bytesPerSec(live?.download_speed.mbps),
            uploadBps: bytesPerSec(live?.upload_speed.mbps),
            peersLive: live?.snapshot.peer_stats.live ?? 0,
            peersSeen: live?.snapshot.peer_stats.seen ?? 0,
            etaSeconds: live?.time_remaining?.duration.secs,
            finished: raw.finished,
            fileProgressBytes: raw.file_progress
        )
    }

    // MARK: - Private mirror of rqbit's stats/v1 JSON
    private struct RawStats: Decodable {
        let state: String
        let file_progress: [Int64]
        let progress_bytes: Int64
        let uploaded_bytes: Int64
        let total_bytes: Int64
        let finished: Bool
        let live: Live?
    }
    private struct Live: Decodable {
        let snapshot: Snapshot
        let download_speed: Speed
        let upload_speed: Speed
        let time_remaining: TimeRemaining?
    }
    private struct Snapshot: Decodable { let peer_stats: PeerStats }
    private struct PeerStats: Decodable { let live: Int; let seen: Int }
    private struct Speed: Decodable { let mbps: Double }
    private struct TimeRemaining: Decodable { let duration: Duration }
    private struct Duration: Decodable { let secs: Int }
}

public struct AddResult: Equatable {
    public let id: String?          // nil in list_only mode
    public let infoHash: String
    public let name: String
    public let outputFolder: String
    public let files: [TorrentFile]
    public init(id: String?, infoHash: String, name: String, outputFolder: String, files: [TorrentFile]) {
        self.id = id; self.infoHash = infoHash; self.name = name
        self.outputFolder = outputFolder; self.files = files
    }
}

public struct ListedTorrent: Equatable {
    public let id: String
    public let infoHash: String
    public let name: String
    public let outputFolder: String
    public init(id: String, infoHash: String, name: String, outputFolder: String) {
        self.id = id; self.infoHash = infoHash; self.name = name; self.outputFolder = outputFolder
    }
}

extension RqbitDecoding {
    /// Decodes both the `list_only` response (id == nil) and a real add
    /// response (id present). `details.files` carries the file list; the index
    /// is the file's position (rqbit's `only_files` selection uses it).
    public static func addResult(from data: Data) throws -> AddResult {
        let raw = try JSONDecoder().decode(RawAdd.self, from: data)
        let files = raw.details.files.enumerated().map { idx, f in
            TorrentFile(index: idx, name: f.name, lengthBytes: f.length, selected: f.included)
        }
        return AddResult(
            id: raw.id.map(String.init),
            infoHash: raw.details.info_hash,
            name: raw.details.name,
            outputFolder: raw.details.output_folder,
            files: files
        )
    }

    public static func list(from data: Data) throws -> [ListedTorrent] {
        let raw = try JSONDecoder().decode(RawList.self, from: data)
        return raw.torrents.map {
            ListedTorrent(id: String($0.id), infoHash: $0.info_hash, name: $0.name, outputFolder: $0.output_folder)
        }
    }

    private struct RawAdd: Decodable {
        let id: Int?
        let details: Details
        struct Details: Decodable {
            let info_hash: String
            let name: String
            let output_folder: String
            let files: [File]
        }
        struct File: Decodable { let name: String; let length: Int64; let included: Bool }
    }
    private struct RawList: Decodable {
        let torrents: [Item]
        struct Item: Decodable { let id: Int; let info_hash: String; let name: String; let output_folder: String }
    }
}
