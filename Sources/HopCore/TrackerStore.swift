import Foundation
import os

/// Reads and writes `TrackerData` as JSON on disk. A file that fails to
/// decode — OR exists but cannot be read — is moved aside rather than
/// overwritten in place, so a bad write never silently erases data the user
/// might want to recover by hand.
public enum TrackerStore {
    private static let fileName = "tracker.json"
    private static let backupFileName = "tracker.json.bak"
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "TrackerStore")

    /// Loads `tracker.json` from `dir`. A missing file loads as `.empty` with no
    /// backup. A file that EXISTS but is unreadable (permissions, transient IO,
    /// not a regular file), or that reads but fails to decode, is renamed to
    /// `tracker.json.bak` — replacing any older backup — before `.empty` is
    /// returned, so the next save can't overwrite recoverable data unseen.
    public static func load(from dir: URL) -> TrackerData {
        let fileURL = dir.appendingPathComponent(fileName)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        guard let raw = try? Data(contentsOf: fileURL) else {
            // Present but unreadable: preserve it before it can be overwritten.
            // A missing file is the normal first-run case — no backup, no log.
            if exists { backUp(fileURL, in: dir, reason: "unreadable") }
            return .empty
        }

        do {
            return try JSONDecoder().decode(TrackerData.self, from: raw)
        } catch {
            backUp(fileURL, in: dir, reason: "undecodable")
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

    /// Move an unusable file aside to the `.bak` slot, replacing any older
    /// backup. One log line per failure — no spam.
    private static func backUp(_ fileURL: URL, in dir: URL, reason: String) {
        let backupURL = dir.appendingPathComponent(backupFileName)
        // Only clear the old .bak once the move actually needs the slot, so a
        // failed move never leaves us with neither backup.
        if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) == nil {
            try? FileManager.default.removeItem(at: backupURL)
            if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) == nil {
                log.error("tracker.json (\(reason, privacy: .public)) could not be backed up")
                return
            }
        }
        log.notice("tracker.json (\(reason, privacy: .public)) moved to \(backupFileName, privacy: .public)")
    }
}
