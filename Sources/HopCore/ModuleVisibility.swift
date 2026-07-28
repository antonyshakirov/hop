/// Whether a module's row belongs on the panel right now.
///
/// Membership decides it: a module shows unless it sits in the inactive bucket.
/// Torrent carries one extra rule, because an empty torrent module is a row that
/// offers to start a download and nothing else — worth hiding for someone who
/// only downloads occasionally.
///
/// The rule deliberately does NOT consult the torrent engine. It used to require
/// the engine to be exactly `.installed`, which quietly made the user's answer
/// conditional on machinery they never asked about: every moment the installer
/// was in some other state — the first launch after an update, a download in
/// flight, a fetch that failed — the row came back for someone who had switched
/// it off (Anton, 2026-07-27). "Do not show this without downloads" is an answer
/// about the row.
public enum ModuleVisibility {
    public static let torrent = "torrent"

    public static func isVisible(
        module: String,
        inactive: [String],
        torrentCount: Int,
        showTorrentWhenEmpty: Bool
    ) -> Bool {
        guard !inactive.contains(module) else { return false }
        if module == torrent, torrentCount == 0, !showTorrentWhenEmpty { return false }
        return true
    }
}
