import XCTest
import CryptoKit
@testable import HopPluginAPI

final class PluginContractTests: XCTestCase {
    let valid = Data(#"{"formatVersion":1,"manifest":{"id":"example.panel","version":"1.0.0","apiVersion":1,"name":"Panel","description":"Panel example","author":"Example","capabilities":["ui.panel"],"settings":[]},"code":"definePlugin({activate(){return {}}})"}"#.utf8)

    func testValidPackageIsParsedWithoutRunningCode() throws {
        let package = try PluginPackage.decode(valid)
        XCTAssertEqual(package.manifest.id, "example.panel")
    }

    func altered(_ changes: (inout [String: Any]) -> Void) throws -> Data {
        var value = try JSONSerialization.jsonObject(with: valid) as! [String: Any]
        changes(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }

    func testPackageRejectsTraversalNativeSizeAndMalformedMetadata() throws {
        for id in ["../timer", "UPPER", "a..b", "a/b", "", ".hidden"] {
            XCTAssertThrowsError(try PluginPackage.decode(altered { value in
                var manifest = value["manifest"] as! [String: Any]; manifest["id"] = id; value["manifest"] = manifest
            }))
        }
        XCTAssertThrowsError(try PluginPackage.decode(Data([0xcf,0xfa,0xed,0xfe])))
        XCTAssertThrowsError(try PluginPackage.decode(Data(repeating: 32, count: 1_048_577)))
        XCTAssertThrowsError(try PluginPackage.decode(altered { $0["code"] = String(repeating: "x", count: 262_145) }))
    }

    func testUnknownCapabilityAndFutureAPIRemainInertMetadata() throws {
        let data = try altered { value in
            var m = value["manifest"] as! [String: Any]; m["apiVersion"] = 2; m["capabilities"] = ["hardware.control"]; value["manifest"] = m
        }
        let package = try PluginPackage.decode(data)
        XCTAssertNotNil(package.compatibilityIssue)
    }

    func testCompleteContributionValidatedBeforeAnyCommandAndPatchSemantics() throws {
        let caps: Set<String> = ["ui.theme","ui.panel","timer.control"]
        let patch = try PluginContributions.decode(Data(#"{"commands":[{"type":"timer.start","seconds":300}],"theme":null}"#.utf8), capabilities: caps)
        XCTAssertEqual(patch.theme, .clear)
        XCTAssertEqual(patch.panel, .unchanged)
        XCTAssertEqual(patch.commands.count, 1)
        for json in [#"{"commands":[{"type":"timer.start","seconds":300}],"panel":{"mode":"replace","nodes":[{"type":"shell"}]}}"#,
                     #"{"theme":{"dark":{"accent":"not-color"}}}"#,
                     #"{"panel":{"mode":"replace","nodes":[{"type":"module","module":"timer"},{"type":"module","module":"timer"}]}}"#,
                     #"{"commands":[{"type":"hardware.control"}]}"#] {
            XCTAssertThrowsError(try PluginContributions.decode(Data(json.utf8), capabilities: caps))
        }
        XCTAssertThrowsError(try PluginContributions.decode(Data(#"{"commands":[{"type":"timer.stop"}]}"#.utf8), capabilities: []))
    }

    func testHostileScalarContributionsThrowWithoutFoundationAbort() {
        for json in [#"{"theme":42}"#, #"{"panel":"scalar"}"#, #"{"commands":42}"#,
                     #"{"commands":null}"#, #"{"commands":[42]}"#, #"{"theme":[]}"#,
                     #"{"panel":true}"#] {
            for grants in [Set<String>(), PluginManifest.capabilities] {
                XCTAssertThrowsError(try PluginContributions.decode(Data(json.utf8), capabilities: grants))
            }
        }
    }

    func testStoreApprovalIsBoundToDigestAndUpdatePreservesSettingsWithoutActivation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PluginStore(directory: directory)
        let record = try store.install(valid, origin: "local")
        XCTAssertFalse(record.wantedEnabled)
        try store.approve(record.id, digest: record.digest, capabilities: ["ui.panel"])
        XCTAssertTrue(try XCTUnwrap(store.record(record.id)).canRun)
        let reloaded = try PluginStore(directory: directory)
        XCTAssertTrue(try XCTUnwrap(reloaded.record(record.id)).canRun)
        let changed = try altered { $0["code"] = "definePlugin({})" }
        let updated = try reloaded.install(changed, origin: "local")
        XCTAssertFalse(updated.canRun)
        XCTAssertFalse(updated.wantedEnabled)
        XCTAssertEqual(updated.grantedCapabilities, [])
        XCTAssertThrowsError(try reloaded.approve(updated.id, digest: record.digest, capabilities: ["ui.panel"]))
        try reloaded.approve(updated.id, digest: updated.digest, capabilities: ["ui.panel"])
        try reloaded.quarantine(updated.id, reason: "runtime_stopped")
        XCTAssertFalse(try XCTUnwrap(PluginStore(directory: directory).record(updated.id)).canRun)
    }

    func testCatalogVerifiesExactBytesSignatureRevisionAndManifestDigest() throws {
        let key = Curve25519.Signing.PrivateKey()
        let package = try PluginPackage.decode(valid)
        let entry = PluginCatalog.Entry(package: package, digest: PluginPackage.digest(valid), packageURL: URL(string: "https://raw.githubusercontent.com/antonyshakirov/hop-plugins/main/packages/example.panel-1.0.0.hopplugin")!)
        let catalog = PluginCatalog(schemaVersion: 1, revision: 4, plugins: [entry], revokedSha256: [])
        let data = try JSONEncoder().encode(catalog)
        let signature = try key.signature(for: data)
        XCTAssertEqual(try PluginCatalog.verified(data, signature: signature, publicKey: key.publicKey.rawRepresentation, minimumRevision: 4).plugins.count, 1)
        XCTAssertThrowsError(try PluginCatalog.verified(data + Data([32]), signature: signature, publicKey: key.publicKey.rawRepresentation, minimumRevision: 0))
        XCTAssertThrowsError(try PluginCatalog.verified(data, signature: signature, publicKey: key.publicKey.rawRepresentation, minimumRevision: 5))
        XCTAssertNoThrow(try entry.verify(valid))
        XCTAssertThrowsError(try entry.verify(valid + Data([32])))
    }

    func testPublishedCatalogAndBothExactPackagesMatchAppContract() throws {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let bytes = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        let signature = try String(contentsOf: root.appendingPathComponent("catalog.json.sig"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = try PluginCatalog.verified(bytes, signature: XCTUnwrap(Data(base64Encoded: signature)), publicKey: XCTUnwrap(Data(base64Encoded: "TpLZ6YZRcZbQS22vxqN6eqMW3qqkQI+BMELhylk8UYc=")), minimumRevision: 1)
        XCTAssertEqual(catalog.plugins.count, 2)
        for entry in catalog.plugins {
            let data = try Data(contentsOf: root.appendingPathComponent(entry.id + "-" + entry.version + ".hopplugin"))
            try entry.verify(data)
            let package = try PluginPackage.decode(data)
            XCTAssertNil(package.compatibilityIssue)
        }
    }

    func testStorageBudgetRejectsTransactionBeforeWritingAndRetainsPreviousStateAfterRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try PluginStore(directory: directory, maximumStateBytes: 4096)
        let first = try store.install(valid, origin: "local")
        try store.approve(first.id, digest: first.digest, capabilities: ["ui.panel"])
        let oversized = try altered { $0["code"] = String(repeating: "x", count: 4096) }
        XCTAssertThrowsError(try store.install(oversized, origin: "local"))
        XCTAssertEqual(store.record(first.id)?.digest, first.digest)
        let restored = try PluginStore(directory: directory, maximumStateBytes: 4096)
        XCTAssertTrue(try XCTUnwrap(restored.record(first.id)).canRun)
        XCTAssertEqual(restored.record(first.id)?.digest, first.digest)
        try Data(repeating: 32, count: 4097).write(to: directory.appendingPathComponent("plugins-v1.json"))
        XCTAssertThrowsError(try PluginStore(directory: directory, maximumStateBytes: 4096))
    }
}
