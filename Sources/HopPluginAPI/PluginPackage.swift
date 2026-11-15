import Foundation
import CryptoKit

public enum PluginError: String, Error, LocalizedError {
    case invalidPackage, incompatible, invalidSettings, invalidContribution, permissionDenied, staleSession
    case invalidSignature, catalogRollback, revoked, runtimeStopped, javascriptError, storageFailure
    case memoryLimit, deadlineExceeded, runtimeUnavailable
    public var errorDescription: String? { rawValue }
}

public enum PluginValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([PluginValue]), object([String: PluginValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self), v.isFinite { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([PluginValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: PluginValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var object: [String: PluginValue]? { if case .object(let v) = self { return v }; return nil }
    public subscript(_ key: String) -> PluginValue? { object?[key] }
}

public struct PluginSetting: Codable, Equatable {
    public let key: String
    public let label: String
    public let type: String
    public let `default`: PluginValue
    public let min: Double?
    public let max: Double?
    public func accepts(_ value: PluginValue) -> Bool {
        switch (type, value) {
        case ("boolean", .bool): return true
        case ("string", .string(let text)): return text.utf8.count <= 4096
        case ("integer", .number(let n)):
            return n.isFinite && n.rounded() == n && n >= (min ?? -1_000_000_000) && n <= (max ?? 1_000_000_000)
        default: return false
        }
    }
}

public struct PluginManifest: Codable, Equatable {
    public let id: String
    public let version: String
    public let apiVersion: Int
    public let name: String
    public let description: String
    public let author: String
    public let capabilities: [String]
    public let settings: [PluginSetting]
    public static let capabilities: Set<String> = ["ui.theme", "ui.panel", "timer.read", "timer.control", "system.read"]
    public static func validID(_ value: String) -> Bool {
        value.utf8.count <= 128 && value.range(of: "^[a-z0-9]+([.-][a-z0-9]+)*$", options: .regularExpression) != nil
    }
    public func validate() throws {
        guard Self.validID(id), version.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$", options: .regularExpression) != nil,
              apiVersion > 0, !name.isEmpty, name.count <= 128, description.count <= 4096, author.count <= 256,
              capabilities.count <= 32, Set(capabilities).count == capabilities.count,
              capabilities.allSatisfy({ !$0.isEmpty && $0.count <= 128 }), settings.count <= 32,
              Set(settings.map(\.key)).count == settings.count else { throw PluginError.invalidPackage }
        for setting in settings {
            guard setting.key.range(of: "^[A-Za-z][A-Za-z0-9_.-]{0,127}$", options: .regularExpression) != nil, !setting.label.isEmpty, setting.label.count <= 128,
                  setting.min.map({ $0.isFinite && abs($0) <= 1_000_000_000 }) ?? true,
                  setting.max.map({ $0.isFinite && abs($0) <= 1_000_000_000 }) ?? true,
                  (setting.min ?? -1_000_000_000) <= (setting.max ?? 1_000_000_000), setting.accepts(setting.default)
            else { throw PluginError.invalidSettings }
        }
    }
}

public struct PluginPackage: Codable, Equatable {
    public let formatVersion: Int
    public let manifest: PluginManifest
    public let code: String
    public var compatibilityIssue: PluginError? {
        manifest.apiVersion == 1 && Set(manifest.capabilities).isSubset(of: PluginManifest.capabilities) ? nil : .incompatible
    }
    public static func decode(_ data: Data) throws -> Self {
        try PluginJSONBounds.check(data, maximumBytes: 1_048_576)
        guard data.count <= 1_048_576, String(data: data, encoding: .utf8) != nil else { throw PluginError.invalidPackage }
        let package = try JSONDecoder().decode(Self.self, from: data)
        guard package.formatVersion == 1, !package.code.isEmpty, package.code.utf8.count <= 262_144,
              !package.code.contains("\0") else { throw PluginError.invalidPackage }
        try package.manifest.validate()
        return package
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

@objc public protocol PluginRuntimeXPC {
    func request(_ data: Data, reply: @escaping (Data) -> Void)
}

public struct PluginRuntimeRequest: Codable {
    public let operation: String
    public let session: UUID
    public let generation: UUID
    public let request: UUID
    public let digest: String
    public let code: String?
    public let sourceDigest: String?
    public let context: PluginValue
    public let event: PluginValue?
    public let action: String?
    public init(operation: String, session: UUID, generation: UUID, request: UUID, digest: String, code: String? = nil,
                context: PluginValue = .object([:]), event: PluginValue? = nil, action: String? = nil) {
        self.operation = operation; self.session = session; self.generation = generation; self.request = request
        self.digest = digest; self.code = code; self.context = context; self.event = event; self.action = action
        sourceDigest = code.map { PluginPackage.digest(Data($0.utf8)) }
    }
}

public struct PluginRuntimeReply: Codable {
    public let generation: UUID
    public let request: UUID
    public let digest: String
    public let result: Data?
    public let error: String?
    public init(_ envelope: PluginRuntimeRequest, result: Data? = nil, error: String? = nil) {
        generation = envelope.generation; request = envelope.request; digest = envelope.digest
        self.result = result; self.error = error
    }
}
