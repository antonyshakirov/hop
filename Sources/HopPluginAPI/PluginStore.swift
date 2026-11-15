import Foundation

public struct PluginRecord: Codable, Identifiable {
    public var id: String { package.manifest.id }
    public let package: PluginPackage
    public let bytes: Data
    public let digest: String
    public let origin: String
    public var wantedEnabled: Bool
    public var grantedDigest: String?
    public var grantedCapabilities: Set<String>
    public var settings: [String: PluginValue]
    public var quarantinedDigest: String?
    public var lastError: String?
    public var canRun: Bool {
        wantedEnabled && package.compatibilityIssue == nil && grantedDigest == digest &&
        grantedCapabilities == Set(package.manifest.capabilities) && quarantinedDigest != digest
    }
}

public final class PluginStore {
    public struct State: Codable {
        public var records: [PluginRecord] = []
        public var catalogRevision = 0
        public var catalogDigest: String?
        public var revoked: Set<String> = []
    }
    public private(set) var state = State()
    private let url: URL
    private let maximumStateBytes: Int
    public init(directory: URL, maximumStateBytes: Int = 48 * 1_048_576) throws {
        guard (1...(48 * 1_048_576)).contains(maximumStateBytes) else { throw PluginError.storageFailure }
        self.maximumStateBytes = maximumStateBytes
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("plugins-v1.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let metadata = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard metadata.isRegularFile == true, metadata.isSymbolicLink != true,
                  let size = metadata.fileSize, size <= maximumStateBytes else { throw PluginError.storageFailure }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: maximumStateBytes + 1) ?? Data()
            guard data.count <= maximumStateBytes else { throw PluginError.storageFailure }
            state = try JSONDecoder().decode(State.self, from: data)
            guard state.records.count <= 64, Set(state.records.map(\.id)).count == state.records.count else { throw PluginError.storageFailure }
            for r in state.records {
                guard try PluginPackage.decode(r.bytes) == r.package, PluginPackage.digest(r.bytes) == r.digest,
                      r.settings.allSatisfy({ key, value in r.package.manifest.settings.first(where: { $0.key == key })?.accepts(value) == true }) else { throw PluginError.storageFailure }
            }
        }
    }
    public func record(_ id: String) -> PluginRecord? { state.records.first { $0.id == id } }
    @discardableResult public func install(_ bytes: Data, origin: String) throws -> PluginRecord {
        let package = try PluginPackage.decode(bytes), digest = PluginPackage.digest(bytes)
        guard !state.revoked.contains(digest) else { throw PluginError.revoked }
        if let existing = record(package.manifest.id), existing.digest == digest { return existing }
        guard state.records.count < 64 || record(package.manifest.id) != nil else { throw PluginError.storageFailure }
        let previous = record(package.manifest.id)
        let settings = Dictionary(uniqueKeysWithValues: package.manifest.settings.map { descriptor in
            let old = previous?.settings[descriptor.key]
            return (descriptor.key, old.flatMap { descriptor.accepts($0) ? $0 : nil } ?? descriptor.default)
        })
        let value = PluginRecord(package: package, bytes: bytes, digest: digest, origin: String(origin.prefix(1024)), wantedEnabled: false,
                                 grantedDigest: nil, grantedCapabilities: [], settings: settings, quarantinedDigest: nil, lastError: nil)
        try transaction { state in
            if let index = state.records.firstIndex(where: { $0.id == value.id }) { state.records[index] = value }
            else { state.records.append(value) }
        }
        return value
    }
    public func approve(_ id: String, digest: String, capabilities: Set<String>) throws {
        try update(id) { record in
            guard record.digest == digest, record.package.compatibilityIssue == nil,
                  capabilities == Set(record.package.manifest.capabilities), !state.revoked.contains(digest) else { throw PluginError.permissionDenied }
            record.grantedDigest = digest; record.grantedCapabilities = capabilities; record.wantedEnabled = true
            record.quarantinedDigest = nil; record.lastError = nil
        }
    }
    public func disable(_ id: String) throws { try update(id) { $0.wantedEnabled = false } }
    public func quarantine(_ id: String, reason: String) throws {
        try update(id) { $0.quarantinedDigest = $0.digest; $0.lastError = String(reason.prefix(256)) }
    }
    public func setting(_ id: String, key: String, value: PluginValue) throws {
        try update(id) { record in
            guard record.package.manifest.settings.first(where: { $0.key == key })?.accepts(value) == true else { throw PluginError.invalidSettings }
            record.settings[key] = value
        }
    }
    public func remove(_ id: String) throws { try transaction { $0.records.removeAll { $0.id == id } } }
    public func acceptCatalog(_ catalog: PluginCatalog, digest: String) throws {
        guard catalog.revision >= state.catalogRevision,
              catalog.revision != state.catalogRevision || state.catalogDigest == nil || state.catalogDigest == digest else { throw PluginError.catalogRollback }
        try transaction { state in
            state.catalogRevision = catalog.revision; state.catalogDigest = digest; state.revoked.formUnion(catalog.revokedSha256)
            for index in state.records.indices where state.revoked.contains(state.records[index].digest) {
                state.records[index].quarantinedDigest = state.records[index].digest
                state.records[index].lastError = PluginError.revoked.rawValue
            }
        }
    }
    private func update(_ id: String, _ operation: (inout PluginRecord) throws -> Void) throws {
        try transaction { value in
            guard let index = value.records.firstIndex(where: { $0.id == id }) else { throw PluginError.invalidPackage }
            try operation(&value.records[index])
        }
    }
    private func transaction(_ operation: (inout State) throws -> Void) throws {
        var next = state
        try operation(&next)
        let data = try JSONEncoder().encode(next)
        guard data.count <= maximumStateBytes else { throw PluginError.storageFailure }
        try data.write(to: url, options: .atomic)
        state = next
    }
}
