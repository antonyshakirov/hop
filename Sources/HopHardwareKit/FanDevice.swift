import Darwin
import Foundation

public enum FanAvailability: String, Codable, Sendable {
    case controllable, fanless, unsupported, unavailable
}

/// Positive fanless identification; an unsuccessful SMC read proves no such thing.
public enum FanDevice {
    // SPEC: Apple model identifiers and fanless references are recorded in docs/spec.md.
    public static func isKnownFanless(_ model: String?) -> Bool {
        guard let model else { return false }
        return ["MacBookAir10,1", "Mac14,2", "Mac14,15", "Mac15,12", "Mac15,13",
                "Mac16,12", "Mac16,13", "Mac17,3", "Mac17,4"].contains(model)
    }

    public static var modelIdentifier: String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, (1...128).contains(size) else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
