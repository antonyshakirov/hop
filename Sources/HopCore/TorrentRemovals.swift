import Foundation

/// SPEC: docs/spec.md "A removal holds until the engine lets go". Tests: TorrentRemovalsTests.
public struct PendingTorrentRemoval: Codable, Equatable {
    public struct Placeholder: Codable, Equatable {
        public let name: String
        public let lengthBytes: Int64
        public init(name: String, lengthBytes: Int64) { self.name = name; self.lengthBytes = lengthBytes }
    }

    public let infoHash: String
    public let deleteFiles: Bool
    public let outputFolder: String?
    public let placeholders: [Placeholder]?

    public init(infoHash: String, deleteFiles: Bool,
                outputFolder: String? = nil, placeholders: [Placeholder]? = nil) {
        self.infoHash = infoHash
        self.deleteFiles = deleteFiles
        self.outputFolder = outputFolder
        self.placeholders = placeholders
    }
}

public struct TorrentRemovals: Codable, Equatable {
    public private(set) var pending: [PendingTorrentRemoval]

    public init(pending: [PendingTorrentRemoval] = []) {
        self.pending = pending
    }

    public var isEmpty: Bool { pending.isEmpty }

    public func contains(_ infoHash: String) -> Bool {
        pending.contains { Self.same($0.infoHash, infoHash) }
    }

    public mutating func add(infoHash: String, deleteFiles: Bool,
                             outputFolder: String? = nil,
                             placeholders: [PendingTorrentRemoval.Placeholder]? = nil) {
        if let i = pending.firstIndex(where: { Self.same($0.infoHash, infoHash) }) {
            let old = pending[i]
            pending[i] = PendingTorrentRemoval(infoHash: old.infoHash,
                                               deleteFiles: old.deleteFiles || deleteFiles,
                                               outputFolder: old.outputFolder ?? outputFolder,
                                               placeholders: old.placeholders ?? placeholders)
        } else {
            pending.append(PendingTorrentRemoval(infoHash: infoHash, deleteFiles: deleteFiles,
                                                 outputFolder: outputFolder, placeholders: placeholders))
        }
    }

    public mutating func cancel(infoHash: String) {
        pending.removeAll { Self.same($0.infoHash, infoHash) }
    }

    /// Drops and returns the removals absent from `listed`, which must be a list the engine returned.
    @discardableResult
    public mutating func settle(listed: [String]) -> [PendingTorrentRemoval] {
        let held = Set(listed.map { $0.lowercased() })
        let done = pending.filter { !held.contains($0.infoHash.lowercased()) }
        pending.removeAll { !held.contains($0.infoHash.lowercased()) }
        return done
    }

    public func visible<T>(_ items: [T], infoHash: (T) -> String) -> [T] {
        items.filter { !contains(infoHash($0)) }
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}
