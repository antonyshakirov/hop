import Foundation
import XCTest
@testable import Hop

final class SoundOutputConfigurationTests: XCTestCase {
    func testVolumeOnlyUpdateDoesNotReactivatePreservedPlayback() {
        let boundary = SoundOutputConfigurationBoundary(), engine = NSObject()
        boundary.apply(outputUID: "a", masterUID: "a", gate: {}, update: {})
        var gates = 0, activations = 0
        boundary.transition(outputUID: "a", masterUID: "a",
            playback: { (ObjectIdentifier(engine), "a", true) },
            gate: { gates += 1 }, update: {}, activate: { activations += 1 })
        XCTAssertEqual(gates, 0)
        XCTAssertEqual(activations, 0)
    }

    func testSameUIDReplacementWaitsForAsyncPrimingInsteadOfImmediateActivation() throws {
        let boundary = SoundOutputConfigurationBoundary(), old = NSObject(), replacement = NSObject()
        boundary.apply(outputUID: "a", masterUID: "a", gate: {}, update: {})
        var engine = old, active = true, ready = true, activations = 0
        XCTAssertNoThrow(try boundary.transition(outputUID: "a", masterUID: "a",
            playback: { (ObjectIdentifier(engine), "a", active) }, gate: {},
            update: { engine = replacement; active = false; ready = false }, activate: {
                activations += 1
                guard ready else { throw SoundFailure.missingDevice }
            }))
        XCTAssertEqual(activations, 0)
        XCTAssertFalse(active); XCTAssertFalse(ready)
        XCTAssertTrue(engine === replacement)
    }

    func testGatedMasterRoleChangeReactivatesThePreservedPlayback() {
        let boundary = SoundOutputConfigurationBoundary(), engine = NSObject()
        boundary.apply(outputUID: "a", masterUID: "a", gate: {}, update: {})
        var events: [String] = []
        boundary.transition(outputUID: "a", masterUID: "b",
            playback: { (ObjectIdentifier(engine), "a", true) },
            gate: { events.append("gate") }, update: { events.append("gain") },
            activate: { events.append("activate") })
        XCTAssertEqual(events, ["gate", "gain", "activate"])
    }

    func testGatedMasterRoleChangeDoesNotActivateAReplacementBeforePriming() {
        let boundary = SoundOutputConfigurationBoundary(), old = NSObject(), replacement = NSObject()
        boundary.apply(outputUID: "a", masterUID: "a", gate: {}, update: {})
        var engine = old, active = true, gates = 0, activations = 0
        boundary.transition(outputUID: "a", masterUID: "b",
            playback: { (ObjectIdentifier(engine), "a", active) }, gate: { gates += 1 },
            update: { engine = replacement; active = false }, activate: { activations += 1 })
        XCTAssertEqual(gates, 1)
        XCTAssertEqual(activations, 0)
        XCTAssertFalse(active)
    }

    func testReusedIdentityWithInactivePlaybackStillWaitsForPriming() {
        let boundary = SoundOutputConfigurationBoundary(), identityToken = NSObject()
        boundary.apply(outputUID: "a", masterUID: "a", gate: {}, update: {})
        var active = true, activations = 0
        boundary.transition(outputUID: "a", masterUID: "b",
            playback: { (ObjectIdentifier(identityToken), "a", active) }, gate: {},
            update: { active = false }, activate: { activations += 1 })
        XCTAssertEqual(activations, 0)
        XCTAssertFalse(active)
    }
}
