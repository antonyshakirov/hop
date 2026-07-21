import Foundation
import os

/// Reads and writes `TodoList` as JSON on disk. Mirrors `TrackerStore`: a file
/// that fails to decode — OR exists but cannot be read — is moved aside rather
/// than overwritten in place, so a bad write never silently erases data the
/// user might recover by hand.
public enum TodosStore {
    private static let fileName = "todos.json"
    private static let backupFileName = "todos.json.bak"
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "TodosStore")

    /// Loads `todos.json` from `dir`. A missing file loads as `.empty` with no
    /// backup. A file that EXISTS but is unreadable, or that reads but fails to
    /// decode, is renamed to `todos.json.bak` — replacing any older backup —
    /// before `.empty` is returned, so the next save can't overwrite recoverable
    /// data unseen.
    public static func load(from dir: URL) -> TodoList {
        let fileURL = dir.appendingPathComponent(fileName)
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        guard let raw = try? Data(contentsOf: fileURL) else {
            if exists { backUp(fileURL, in: dir, reason: "unreadable") }
            return .empty
        }

        do {
            return try JSONDecoder().decode(TodoList.self, from: raw)
        } catch {
            backUp(fileURL, in: dir, reason: "undecodable")
            return .empty
        }
    }

    /// Writes `list` to `todos.json` in `dir` as a single atomic file
    /// replacement, so a crash mid-write can't leave a truncated file.
    public static func save(_ list: TodoList, to dir: URL) throws {
        let fileURL = dir.appendingPathComponent(fileName)
        let encoded = try JSONEncoder().encode(list)
        try encoded.write(to: fileURL, options: .atomic)
    }

    /// Move an unusable file aside to the `.bak` slot, replacing any older
    /// backup. One log line per failure — no spam.
    private static func backUp(_ fileURL: URL, in dir: URL, reason: String) {
        let backupURL = dir.appendingPathComponent(backupFileName)
        if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) == nil {
            try? FileManager.default.removeItem(at: backupURL)
            if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) == nil {
                log.error("todos.json (\(reason, privacy: .public)) could not be backed up")
                return
            }
        }
        log.notice("todos.json (\(reason, privacy: .public)) moved to \(backupFileName, privacy: .public)")
    }
}
