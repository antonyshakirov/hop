import Foundation
import os

/// Reads and writes `TodoList` as JSON on disk. Mirrors `TrackerStore`: a file
/// that fails to decode — OR exists but cannot be read — is moved aside rather
/// than overwritten in place, so a bad write never silently erases data the
/// user might recover by hand.
public enum TodosStore {
    private static let fileName = "todos.json"
    private static let backupFileName = "todos.json.bak"
    /// Where completed items go when the list lets them go: the same shape as
    /// `todos.json`, appended to, never read back by the app — it is there so
    /// nothing ticked off is lost, and so a script can look things up.
    private static let archiveFileName = "todos-archive.json"
    private static let archiveBackupFileName = "todos-archive.json.bak"
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

    /// Appends `items` to `todos-archive.json` in `dir`. The archive is read,
    /// extended and written back atomically; one that exists but cannot be read
    /// or decoded is moved aside to its own `.bak` first, the way the list is,
    /// so a bad file costs a backup rather than what was about to be archived.
    public static func archive(_ items: [TodoItem], to dir: URL) throws {
        guard !items.isEmpty else { return }
        let fileURL = dir.appendingPathComponent(archiveFileName)
        var archived = TodoList.empty
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let raw = try? Data(contentsOf: fileURL) {
                if let decoded = try? JSONDecoder().decode(TodoList.self, from: raw) {
                    archived = decoded
                } else {
                    backUp(fileURL, in: dir, reason: "undecodable", as: archiveBackupFileName)
                }
            } else {
                backUp(fileURL, in: dir, reason: "unreadable", as: archiveBackupFileName)
            }
        }
        archived.items.append(contentsOf: items)
        let encoded = try JSONEncoder().encode(archived)
        try encoded.write(to: fileURL, options: .atomic)
    }

    /// Move an unusable file aside to the `.bak` slot, replacing any older
    /// backup. One log line per failure — no spam.
    private static func backUp(_ fileURL: URL, in dir: URL, reason: String,
                               as backupFileName: String = backupFileName) {
        let backupURL = dir.appendingPathComponent(backupFileName)
        if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) == nil {
            try? FileManager.default.removeItem(at: backupURL)
            if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) == nil {
                log.error("\(fileURL.lastPathComponent, privacy: .public) (\(reason, privacy: .public)) could not be backed up")
                return
            }
        }
        log.notice("\(fileURL.lastPathComponent, privacy: .public) (\(reason, privacy: .public)) moved to \(backupFileName, privacy: .public)")
    }
}
