import Foundation
import HopCore

/// The rqbit torrent engine as a downloadable helper: the generic mechanism
/// (fetch, verify the Ed25519 signature, install into Application Support)
/// lives in ToolInstaller — this only says WHICH binary and where it comes from.
@MainActor
final class TorrentEngineInstaller: ToolInstaller {
    static let manifestURL = "https://hop.tools/downloads/hop/engine/engine.json"
    /// SPEC: 8.1.1 sends no User-Agent, and Cloudflare-fronted trackers answer it with 403.
    static let minimumVersion = "9.0.1"
    /// Kept as its own name because the engine card quotes the size in its copy.
    var engineSizeBytes: Int64 { sizeBytes }

    init() {
        super.init(manifestURL: Self.manifestURL,
                   folderName: "torrent-engine",
                   binaryName: "rqbit",
                   minimumVersion: Self.minimumVersion)
    }
}
