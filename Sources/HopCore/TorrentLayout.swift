import Foundation

/// Where a torrent's payload is written under the folder the user picked.
///
/// rqbit lays files out at `output_folder/<relative path>`, and a multi-file
/// torrent's file paths are relative to its content root — they do NOT include
/// the torrent's own name (e.g. `Eng/ep1.srt`, `ep1.avi`). Passing the chosen
/// folder verbatim therefore scatters those loose files (and the torrent's own
/// `Eng/`, `Rus/` subdirectories) directly into it. We nest a multi-file torrent
/// under a folder named after the torrent — exactly what rqbit does on its own
/// when no `output_folder` is supplied — so its internal structure is preserved
/// inside one tidy container. Single-file torrents write directly: their one file
/// IS the payload, and a folder named after it would be noise.
public enum TorrentLayout {
    /// The wrapper subfolder name to append to the chosen folder, or nil to write
    /// straight into it. Nil for single-file torrents and for an unusable name.
    public static func subfolder(torrentName: String, fileCount: Int) -> String? {
        guard fileCount > 1 else { return nil }
        let safe = sanitize(torrentName)
        return safe.isEmpty ? nil : safe
    }

    /// True if any file's relative path would escape the output folder — a hostile
    /// `.torrent` with absolute (`/…`) or traversal (`../`) members, or a NUL. rqbit
    /// sanitizes these today, but we don't rely solely on a downgradeable engine:
    /// reject such a torrent before writing anything.
    public static func hasUnsafePath(_ names: [String]) -> Bool {
        for name in names {
            if name.hasPrefix("/") || name.contains("\0") { return true }
            if name.split(separator: "/", omittingEmptySubsequences: false).contains("..") { return true }
        }
        return false
    }

    /// The on-disk path(s) whose disappearance means the torrent's payload was
    /// deleted out from under the engine. A single-file torrent lives directly at
    /// `outputFolder/<file name>`; a multi-file torrent is nested inside the
    /// `outputFolder` wrapper, so the wrapper itself is the probe. Empty when there
    /// is no file detail to key off (e.g. a restore that couldn't list files) so a
    /// caller never false-flags a torrent whose layout it can't resolve.
    public static func payloadProbePaths(outputFolder: String, fileNames: [String]) -> [String] {
        guard !fileNames.isEmpty else { return [] }
        if fileNames.count == 1 {
            return [(outputFolder as NSString).appendingPathComponent(fileNames[0])]
        }
        return [outputFolder]
    }

    /// True when the payload is considered gone: there is a probe path and NONE of
    /// the probe paths exist on disk. `exists` is injected so the decision is unit
    /// testable without touching the filesystem. Returns false when no probe can be
    /// formed — absence of information is never treated as deletion.
    public static func payloadMissing(outputFolder: String, fileNames: [String],
                                      exists: (String) -> Bool) -> Bool {
        let probes = payloadProbePaths(outputFolder: outputFolder, fileNames: fileNames)
        guard !probes.isEmpty else { return false }
        return !probes.contains(where: exists)
    }

    /// Reduce a torrent name to a safe single path component: path separators and
    /// NUL become "-", surrounding whitespace is trimmed, and a name that resolves
    /// to the current/parent directory ("."/"..") is rejected.
    static func sanitize(_ name: String) -> String {
        var s = name
        for bad in ["/", ":", "\0"] { s = s.replacingOccurrences(of: bad, with: "-") }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reject a name with no real content: one made only of separators, dots or
        // dashes would resolve to "."/".." or leave a junk folder like "-".
        let stripped = s.trimmingCharacters(in: CharacterSet(charactersIn: "-. "))
        return stripped.isEmpty ? "" : s
    }
}
