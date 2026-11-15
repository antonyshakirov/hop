import Foundation
import CryptoKit

public struct PluginCatalog: Codable {
    public struct Entry: Codable, Identifiable {
        public let id: String
        public let version: String
        public let apiVersion: Int
        public let name: String
        public let description: String
        public let author: String
        public let capabilities: [String]
        public let packageURL: URL
        public let sha256: String
        public init(package: PluginPackage, digest: String, packageURL: URL) {
            let m = package.manifest
            id = m.id; version = m.version; apiVersion = m.apiVersion; name = m.name
            description = m.description; author = m.author; capabilities = m.capabilities
            sha256 = digest; self.packageURL = packageURL
        }
        public func verify(_ data: Data) throws {
            let m = try PluginPackage.decode(data).manifest
            guard PluginPackage.digest(data) == sha256, m.id == id, m.version == version, m.apiVersion == apiVersion,
                  m.name == name, m.description == description, m.author == author, m.capabilities == capabilities else { throw PluginError.invalidPackage }
        }
    }
    public let schemaVersion: Int
    public let revision: Int
    public let plugins: [Entry]
    public let revokedSha256: [String]
    public init(schemaVersion: Int, revision: Int, plugins: [Entry], revokedSha256: [String]) {
        self.schemaVersion = schemaVersion; self.revision = revision; self.plugins = plugins; self.revokedSha256 = revokedSha256
    }
    public static func verified(_ data: Data, signature: Data, publicKey: Data, minimumRevision: Int) throws -> Self {
        try PluginJSONBounds.check(data, maximumBytes: 1_048_576)
        guard data.count <= 1_048_576, signature.count == 64,
              try Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signature, for: data) else { throw PluginError.invalidSignature }
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 1, catalog.revision >= 1, catalog.revision >= minimumRevision else { throw PluginError.catalogRollback }
        guard catalog.plugins.count <= 512, Set(catalog.plugins.map(\.id)).count == catalog.plugins.count,
              catalog.revokedSha256.count <= 4096,
              catalog.revokedSha256.allSatisfy({ $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }) else { throw PluginError.invalidPackage }
        for entry in catalog.plugins {
            guard PluginManifest.validID(entry.id), entry.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  entry.packageURL.scheme == "https", entry.packageURL.host != nil, entry.packageURL.user == nil,
                  entry.packageURL.password == nil, entry.apiVersion == 1,
                  entry.version.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$", options: .regularExpression) != nil,
                  entry.packageURL.absoluteString == "https://raw.githubusercontent.com/antonyshakirov/hop-plugins/main/packages/\(entry.id)-\(entry.version).hopplugin",
                  !entry.name.isEmpty, entry.name.count <= 128, entry.description.count <= 4096, entry.author.count <= 256,
                  entry.capabilities.count <= 32, Set(entry.capabilities).count == entry.capabilities.count,
                  Set(entry.capabilities).isSubset(of: PluginManifest.capabilities) else { throw PluginError.invalidPackage }
        }
        return catalog
    }
}
