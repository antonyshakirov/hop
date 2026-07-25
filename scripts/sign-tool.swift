// Helper-tool signing: swift scripts/sign-tool.swift <binary> [download-url]
//
// Downloadable helpers (the rqbit torrent engine, the 7-Zip archiver) are
// installed ONLY after an Ed25519 signature by our key checks out, so this
// script is the single way a new tool becomes installable. It writes
// "<binary>.sig" next to the file and prints the manifest JSON to paste beside
// it on the site.
//
// The key is created on first run at ~/.minimo-torrent-engine-key (do NOT
// commit!); its public half is printed for pasting into
// ToolInstaller.toolPublicKeyBase64.
import CryptoKit
import Foundation

let keyPath = NSString(string: "~/.minimo-torrent-engine-key").expandingTildeInPath
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
print("public key (for ToolInstaller.toolPublicKeyBase64):")
print(key.publicKey.rawRepresentation.base64EncodedString())

guard CommandLine.arguments.count > 1 else { exit(0) }
let binaryPath = CommandLine.arguments[1]
guard let binary = FileManager.default.contents(atPath: binaryPath) else {
    fputs("file not found: \(binaryPath)\n", stderr); exit(1)
}

let signature = try! key.signature(for: binary)
try! signature.write(to: URL(fileURLWithPath: binaryPath + ".sig"))
print("signature: \(binaryPath).sig")

// The manifest the installer fetches. The URL is passed in because the binary
// is served from the CDN, not from where it was signed.
let name = (binaryPath as NSString).lastPathComponent
let url = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "https://hop-dl.b-cdn.net/downloads/hop/tools/\(name)"
let digest = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
print("""

manifest:
{
  "version": "",
  "url": "\(url)",
  "sig": "\(url).sig",
  "size": \(binary.count),
  "sha256": "\(digest)"
}
""")
