import Foundation
import HopCore

/// The rqbit torrent engine as a downloadable helper: the generic mechanism
/// (fetch, verify the Ed25519 signature, install into Application Support)
/// lives in ToolInstaller — this only says WHICH binary and where it comes from.
@MainActor
final class TorrentEngineInstaller: ToolInstaller {
    static let manifestURL = "https://hop.tools/downloads/hop/engine/engine.json"
    /// Kept as its own name because the engine card quotes the size in its copy.
    var engineSizeBytes: Int64 { sizeBytes }

    init() {
        super.init(manifestURL: Self.manifestURL,
                   folderName: "torrent-engine",
                   binaryName: "rqbit")
    }
}
