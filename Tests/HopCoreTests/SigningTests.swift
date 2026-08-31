import XCTest
@testable import HopCore

/// SPEC: docs/spec.md — "Signing, notarisation, and why permissions must
/// survive an update". Nothing below shows up in a build or on the machine that
/// made the release; it shows up on the machine of somebody installing Hop for
/// the first time.
final class SigningTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // HopCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private func text(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(path))
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
        return try XCTUnwrap(parsed)
    }

    func testAppleEventsAreEntitledUnderTheHardenedRuntime() throws {
        let entitlements = try plist("scripts/Hop.entitlements")
        XCTAssertEqual(
            entitlements["com.apple.security.automation.apple-events"] as? Bool, true,
            "without this the iWork export and the lid switch fail under the hardened runtime")
    }

    func testAppleEventsCarryAUsageDescription() throws {
        let info = try plist("scripts/Info.plist")
        let description = info["NSAppleEventsUsageDescription"] as? String
        XCTAssertNotNil(description, "macOS kills a process that sends an Apple event without one")
        XCTAssertFalse(description?.isEmpty ?? true)
    }

    func testEveryBundleIsSignedThroughTheOneSigningHelper() throws {
        for script in ["scripts/build-app.sh", "scripts/release.sh"] {
            let source = try text(script)
            XCTAssertTrue(source.contains("source scripts/signing.sh"),
                          "\(script) signs outside the shared helper")
            XCTAssertTrue(source.contains("hop_sign_app"),
                          "\(script) does not use the shared signing options")
        }
    }

    func testTheSigningHelperTurnsOnTheHardenedRuntimeAndTheEntitlements() throws {
        let source = try text("scripts/signing.sh")
        XCTAssertTrue(source.contains("--options runtime"),
                      "a build without the hardened runtime cannot be notarised")
        XCTAssertTrue(source.contains("--entitlements"),
                      "a build signed without entitlements loses its Apple events")
    }

    func testAReleaseIsNotarisedAndStapled() throws {
        let source = try text("scripts/release.sh")
        XCTAssertTrue(source.contains("notarytool submit"),
                      "a release that is never submitted is blocked on every first install")
        XCTAssertTrue(source.contains("stapler staple"),
                      "without a stapled ticket a first launch offline is blocked")
        XCTAssertFalse(source.contains("--sign \"-\""),
                       "an ad-hoc signature in the release path resets every user's permissions")
    }

    func testTheReleaseGateChecksWhatTheUsersMacWillDecide() throws {
        let source = try text("scripts/verify-release.sh")
        XCTAssertTrue(source.contains("spctl"),
                      "the gate has to ask Gatekeeper about the served copy, not just unpack it")
        XCTAssertTrue(source.contains("stapler validate"))
    }
}
