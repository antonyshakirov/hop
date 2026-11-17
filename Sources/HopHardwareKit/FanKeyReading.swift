import Foundation

/// Read-only, fixed-key support data. It is never an interface for choosing SMC keys.
public struct FanKeyReading: Codable, Equatable, Sendable {
    public static let keys = ["FNum", "Ftst", "FS! "] + (0..<8).flatMap { index in
        ["Ac", "Mn", "Mx", "Tg", "Md", "md"].map { "F\(index)\($0)" }
    }
    public let key: String
    public let type: String?
    public let number: Double?
    public let readable: Bool
    public let kernel: Int32?
    public let result: UInt8?

    public init(key: String, type: String?, number: Double?, readable: Bool, error: SMCError? = nil) {
        self.key = key
        self.type = type.flatMap { $0.utf8.count == 4 && $0.utf8.allSatisfy { (32...126).contains($0) } ? $0 : nil }
        self.number = number.flatMap { $0.isFinite && (-1...65535).contains($0) ? $0 : nil }
        self.readable = readable
        if let error, case let .callFailed(_, kernel, result) = error {
            self.kernel = kernel; self.result = result
        } else { kernel = nil; result = nil }
    }
    public var valid: Bool {
        Self.keys.contains(key)
            && (type.map { $0.utf8.count == 4 && $0.utf8.allSatisfy { (32...126).contains($0) } } ?? true)
            && (number.map { $0.isFinite && (-1...65535).contains($0) } ?? true)
    }
}

public enum FanControlSupport {
    /// Manual-control semantics, independent of the unchanged version-1 update protocol.
    public static let revision = 2
}
