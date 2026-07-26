import Foundation

/// Owns the hidden directory used while an archive is being extracted. A launch
/// identifier separates live concurrent jobs from debris left by an older app
/// process, so cleanup can be both eager and safe.
public enum ArchiveStaging {
    private static let prefix = ".hop-unpack-"
    private static let sessionSeparator = "--"

    public static func directoryName(
        sessionID: UUID,
        operationID: UUID
    ) -> String {
        "\(prefix)\(sessionID.uuidString)\(sessionSeparator)\(operationID.uuidString)"
    }

    public static func isManagedDirectoryName(_ name: String) -> Bool {
        guard name.hasPrefix(prefix) else { return false }
        let suffix = String(name.dropFirst(prefix.count))
        if UUID(uuidString: suffix) != nil { return true }
        let parts = suffix.components(separatedBy: sessionSeparator)
        return parts.count == 2
            && UUID(uuidString: parts[0]) != nil
            && UUID(uuidString: parts[1]) != nil
    }

    public static func belongsToSession(
        _ name: String,
        sessionID: UUID
    ) -> Bool {
        name.hasPrefix("\(prefix)\(sessionID.uuidString)\(sessionSeparator)")
            && isManagedDirectoryName(name)
    }

    /// Remove only real managed directories from previous launches. Symlinks,
    /// regular files and lookalike names are user data, even when their names
    /// start with Hop's prefix.
    public static func removeOrphans(
        in destination: URL,
        preserving sessionID: UUID,
        fileManager: FileManager = .default
    ) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants])
        for url in urls {
            let name = url.lastPathComponent
            guard isManagedDirectoryName(name),
                  !belongsToSession(name, sessionID: sessionID) else { continue }
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true,
                  values.isSymbolicLink != true else { continue }
            try fileManager.removeItem(at: url)
        }
    }

    /// Sweep old debris, create one session-scoped staging directory, run the
    /// operation and remove its directory on every normal or thrown exit.
    public static func withDirectory<Value>(
        in destination: URL,
        sessionID: UUID,
        operationID: UUID = UUID(),
        fileManager: FileManager = .default,
        operation: (URL) throws -> Value
    ) throws -> Value {
        try removeOrphans(
            in: destination,
            preserving: sessionID,
            fileManager: fileManager)
        let staging = destination.appendingPathComponent(
            directoryName(sessionID: sessionID, operationID: operationID))
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: false)
        do {
            let value = try operation(staging)
            try removeIfPresent(staging, fileManager: fileManager)
            return value
        } catch {
            do {
                try removeIfPresent(staging, fileManager: fileManager)
            } catch {
                throw error
            }
            throw error
        }
    }

    private static func removeIfPresent(
        _ url: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
