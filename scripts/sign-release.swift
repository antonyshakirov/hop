// Release signing: swift scripts/sign-release.swift Hop.zip
// The key is created on first run at ~/.minimo-release-key (do NOT commit!),
// the public half is printed for pasting into UpdateChecker.updatePublicKeyBase64.
import CryptoKit
import Foundation

let keyPath = NSString(string: "~/.minimo-release-key").expandingTildeInPath
let key: Curve25519.Signing.PrivateKey
if let data = FileManager.default.contents(atPath: keyPath) {
    key = try! Curve25519.Signing.PrivateKey(rawRepresentation: data)
} else {
    key = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(
        atPath: keyPath, contents: key.rawRepresentation,
        attributes: [.posixPermissions: 0o600]
    )
    print("new key created: \(keyPath)")
}
print("public key (for UpdateChecker.updatePublicKeyBase64):")
print(key.publicKey.rawRepresentation.base64EncodedString())

guard CommandLine.arguments.count > 1 else { exit(0) }
let zipPath = CommandLine.arguments[1]
guard let zip = FileManager.default.contents(atPath: zipPath) else {
    fputs("file not found: \(zipPath)\n", stderr); exit(1)
}
let signature = try! key.signature(for: zip)
try! signature.write(to: URL(fileURLWithPath: zipPath + ".sig"))
print("signature: \(zipPath).sig")
