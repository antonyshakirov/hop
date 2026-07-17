import Foundation
import CryptoKit

/// The engine-update manifest hosted next to the binary (engine.json).
public struct EngineManifest: Decodable, Equatable {
    public let version: String
    public let url: String
    public let sig: String
    public let size: Int64?
    public let sha256: String?
}

public enum EngineSignature {
    /// Ed25519 verification of `signature` over `data` using a base64 raw public
    /// key. Any malformed input returns false — a bad key or signature never
    /// "passes". This is the only gate to installing a downloaded engine binary.
    public static func isValid(signature: Data, for data: Data, publicKeyBase64: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
