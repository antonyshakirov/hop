import Foundation

/// Reads and writes `TrackerData` as JSON on disk. A file that fails to
/// decode is moved aside rather than overwritten in place, so a bad write
/// never silently erases data the user might want to recover by hand.
public enum TrackerStore {
    private static let fileName = "tracker.json"
    private static let backupFileName = "tracker.json.bak"

    /// Loads `tracker.json` from `dir`. A missing or unreadable file loads
    /// as `.empty` with no backup. Content that fails to decode is renamed
    /// to `tracker.json.bak`, replacing any older backup, and `.empty` is
    /// returned so the app can still launch.
    public static func load(from dir: URL) -> TrackerData {
        let fileURL = dir.appendingPathComponent(fileName)
        guard let raw = try? Data(contentsOf: fileURL) else { return .empty }

        do {
            return try JSONDecoder().decode(TrackerData.self, from: raw)
        } catch {
            let backupURL = dir.appendingPathComponent(backupFileName)
            // Only clear the old .bak once the move actually needs the
            // slot, so a failed move never leaves us with neither backup.
            if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) == nil {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            }
            return .empty
        }
    }

    /// Writes `data` to `tracker.json` in `dir` as a single atomic file
    /// replacement, so a crash mid-write can't leave a truncated file.
    public static func save(_ data: TrackerData, to dir: URL) throws {
        let fileURL = dir.appendingPathComponent(fileName)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }
}
