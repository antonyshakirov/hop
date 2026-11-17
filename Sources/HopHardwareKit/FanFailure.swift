import Foundation

/// Bounded hardware diagnostics; never carries arbitrary error descriptions or user data.
public struct FanFailure: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case takeover, targetWrite, targetReadback, modeReadback, release
    }
    public let phase: Phase
    public let key: String?
    public let expected: Double?
    public let actual: Double?
    public let kernel: Int32?
    public let result: UInt8?

    public init(phase: Phase, key: String? = nil, expected: Double? = nil,
                actual: Double? = nil, error: Error? = nil) {
        self.phase = phase; self.key = key
        self.expected = expected.flatMap { $0.isFinite && (-1...65535).contains($0) ? $0 : nil }
        self.actual = actual.flatMap { $0.isFinite && (-1...65535).contains($0) ? $0 : nil }
        if let error = error as? SMCError, case let .callFailed(_, kernel, result) = error {
            self.kernel = kernel; self.result = result
        } else { kernel = nil; result = nil }
    }

    public var valid: Bool {
        return (key.map { FanKeyReading.keys.contains($0) } ?? true)
            && [expected, actual].allSatisfy { $0.map { $0.isFinite && (-1...65535).contains($0) } ?? true }
    }
}
