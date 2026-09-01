import Foundation
import HopCore

/// The repacking helper as a downloadable tool: the generic mechanism (fetch,
/// verify the Ed25519 signature, install into Application Support) lives in
/// ToolInstaller — this only says WHICH binary and where it comes from.
///
/// It is a minimal LGPL build of ffmpeg: Matroska in, MP4 out, no encoders and
/// no GPL parts compiled in at all (see `scripts/build-remuxer.sh`, which is
/// also how anyone can rebuild exactly what we ship). Hop bundles no
/// third-party binaries — this one arrives only when an mkv or a webm does.
@MainActor
final class RemuxInstaller: ToolInstaller {
    static let manifestURL = "https://hop.tools/downloads/hop/remuxer/remuxer.json"

    init() {
        super.init(manifestURL: Self.manifestURL,
                   folderName: "remuxer",
                   binaryName: "ffmpeg")
    }
}
