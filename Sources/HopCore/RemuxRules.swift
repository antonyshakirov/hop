import Foundation

/// Repacking a Matroska file into MP4 without touching the picture.
///
/// macOS cannot open mkv or webm at all — AVFoundation refuses them whatever is
/// inside — so the converter used to name them unsupported on arrival. But the
/// PICTURE inside is usually h264 or hevc, which MP4 holds perfectly well: the
/// container is the whole problem. Swapping it is a copy, not an encode — it
/// takes a second, loses nothing, and hands the normal pipeline a file it can
/// read (decided 2026-08-04). The copy is done by a downloaded helper, because
/// the system has no muxer of its own to lend.
public enum RemuxRules {
    /// The containers the system will not open and the helper can repack.
    public static let repackableExtensions: Set<String> = ["mkv", "webm"]

    public static func needsRepacking(_ url: URL) -> Bool {
        repackableExtensions.contains(url.pathExtension.lowercased())
    }

    /// What MP4 is willing to carry. Anything else has to be re-encoded, which
    /// a repack deliberately never does — the honest answer there is to say so.
    /// (Subtitle and data tracks are dropped rather than judged, so they are
    /// not in either list.)
    public static let mp4Codecs: Set<String> = [
        "h264", "hevc", "av1", "vp9", "mpeg4", "prores",
        "aac", "mp3", "opus", "ac3", "eac3", "alac", "flac",
    ]

    /// The typical webm pairing is exactly the one MP4 cannot hold, which is
    /// why the failure has to read as an explanation rather than an error.
    public static func canRepack(videoCodec: String?, audioCodec: String?) -> Bool {
        let tracks = [videoCodec, audioCodec].compactMap { $0?.lowercased() }
        guard !tracks.isEmpty else { return false }
        return tracks.allSatisfy { mp4Codecs.contains($0) }
    }

    /// The helper's arguments: copy the first video and (if there is one) the
    /// first audio track into MP4, and leave everything else behind.
    ///
    /// `-map 0:a:0?` is optional on purpose — a silent screen recording is a
    /// perfectly ordinary mkv, and demanding an audio track would fail it.
    /// Subtitle and data tracks are dropped: MP4 can hold neither of them the
    /// way Matroska does, and a repack that quietly re-encoded subtitles would
    /// be doing something nobody asked for.
    public static func arguments(input: URL, output: URL) -> [String] {
        [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", input.path,
            "-map", "0:v:0", "-map", "0:a:0?",
            "-c", "copy", "-sn", "-dn",
            "-movflags", "+faststart",
            output.path,
        ]
    }

    /// Whether the helper's complaint is "this codec cannot go into MP4"
    /// rather than a broken file. The message is worth reading because the two
    /// deserve different words on screen: one is a limit, the other a fault.
    public static func isCodecRefusal(_ stderr: String) -> Bool {
        let text = stderr.lowercased()
        return text.contains("could not find tag for codec")
            || text.contains("only version 1 and 2 supported")
            || text.contains("track 1 with codec")
            || (text.contains("codec") && text.contains("not supported in container"))
    }

    /// Where the repacked file goes while the rest of the pipeline works on it:
    /// a temporary of our own, named after the source so a log or a crash
    /// report still says which file it was.
    public static func temporaryOutput(for input: URL, in directory: URL,
                                       token: String) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        return directory
            .appendingPathComponent("hop-repack-\(token)-\(stem)")
            .appendingPathExtension("mp4")
    }
}
