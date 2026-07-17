import XCTest
import CryptoKit
@testable import HopCore

final class EngineSignatureTests: XCTestCase {
    func testValidSignatureVerifies() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("hello engine".utf8)
        let sig = try key.signature(for: data)
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertTrue(EngineSignature.isValid(signature: sig, for: data, publicKeyBase64: pub))
    }
    func testTamperedDataFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sig = try key.signature(for: Data("original".utf8))
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertFalse(EngineSignature.isValid(signature: sig, for: Data("tampered".utf8), publicKeyBase64: pub))
    }
    func testWrongKeyFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("hello".utf8)
        let sig = try key.signature(for: data)
        let otherPub = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        XCTAssertFalse(EngineSignature.isValid(signature: sig, for: data, publicKeyBase64: otherPub))
    }
    func testMalformedKeyStringFails() {
        XCTAssertFalse(EngineSignature.isValid(signature: Data(), for: Data("x".utf8), publicKeyBase64: "!!!not base64!!!"))
    }
    func testManifestDecodes() throws {
        let json = Data(#"{"version":"8.1.1","url":"https://x/rqbit","sig":"https://x/rqbit.sig","size":12345,"sha256":"abc"}"#.utf8)
        let m = try JSONDecoder().decode(EngineManifest.self, from: json)
        XCTAssertEqual(m.version, "8.1.1")
        XCTAssertEqual(m.url, "https://x/rqbit")
        XCTAssertEqual(m.sig, "https://x/rqbit.sig")
        XCTAssertEqual(m.size, 12345)
    }
    func testManifestDecodesWithoutOptionals() throws {
        let json = Data(#"{"version":"8.1.1","url":"https://x/rqbit","sig":"https://x/rqbit.sig"}"#.utf8)
        let m = try JSONDecoder().decode(EngineManifest.self, from: json)
        XCTAssertNil(m.size)
        XCTAssertNil(m.sha256)
    }
}
