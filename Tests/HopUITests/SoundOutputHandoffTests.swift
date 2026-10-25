import HopCore
import XCTest
@testable import Hop

final class SoundOutputHandoffTests: XCTestCase {
    private final class Endpoints {
        var events: [String] = []
        var rejectMute = false
        func make() -> SoundOutputHandoff {
            SoundOutputHandoff(setSourceMuted: { [self] value in
                events.append(value ? "guard" : "direct")
                if value && rejectMute { throw SoundFailure.system(-1) }
            }, setPlaybackEnabled: { [self] in events.append($0 ? "play" : "gate") },
            releaseSource: { [self] in events.append("release") },
            stopPlayback: { [self] in events.append("stop") },
            discardQueued: { [self] in events.append("discard") })
        }
    }

    func testDefaultAudibleWarmupKeepsOriginalUntilReadyThenGuardsBeforePlaying() throws {
        let io = Endpoints(), handoff = io.make()
        try handoff.prepare(outputUID: "speakers", followsSystem: true, settings: .init())
        XCTAssertTrue(io.events.contains("direct"))
        XCTAssertFalse(io.events.contains("guard")); XCTAssertFalse(io.events.contains("play"))
        XCTAssertTrue(try handoff.ready(for: "speakers"))
        XCTAssertEqual(Array(io.events.suffix(2)), ["guard", "play"])
        XCTAssertFalse(io.events.contains("discard"), "First activation must retain the primed capture buffer")
    }

    func testExplicitDestinationGuardsImmediatelyEvenWhenItMatchesDefault() throws {
        let io = Endpoints(), handoff = io.make()
        try handoff.prepare(outputUID: "speakers", followsSystem: false, settings: .init())
        XCTAssertTrue(io.events.contains("guard"))
        XCTAssertFalse(io.events.contains("direct")); XCTAssertFalse(io.events.contains("play"))
    }

    func testMutedZeroAndMissingTargetCannotWarmThroughOriginalOutput() throws {
        var muted = SoundChannelSettings(); muted.muted = true
        var zero = SoundChannelSettings(); zero.gain = 0
        let cases: [(String?, SoundChannelSettings)] = [("speakers", muted), ("speakers", zero), (nil, .init())]
        for (uid, settings) in cases {
            let io = Endpoints(), handoff = io.make()
            try handoff.prepare(outputUID: uid, followsSystem: true, settings: settings)
            XCTAssertTrue(io.events.contains("guard")); XCTAssertFalse(io.events.contains("direct"))
            if uid == nil { XCTAssertFalse(try handoff.ready(for: "speakers")) }
            XCTAssertFalse(io.events.contains("play"))
        }
    }

    func testPendingMuteAndDeviceLossAcquireGuardBeforeReadiness() throws {
        for loseDevice in [false, true] {
            let io = Endpoints(), handoff = io.make()
            try handoff.prepare(outputUID: "speakers", followsSystem: true, settings: .init())
            io.events.removeAll()
            var settings = SoundChannelSettings(); settings.muted = !loseDevice
            try handoff.reconcile(outputUID: loseDevice ? nil : "speakers", followsSystem: true, settings: settings)
            XCTAssertTrue(io.events.contains("guard")); XCTAssertFalse(io.events.contains("play"))
            if loseDevice { XCTAssertFalse(try handoff.ready(for: "speakers")) }
        }
    }

    func testStaleDestinationReadinessCannotActivateOldOutput() throws {
        let io = Endpoints(), handoff = io.make()
        try handoff.prepare(outputUID: "a", followsSystem: true, settings: .init())
        try handoff.reconcile(outputUID: "b", followsSystem: true, settings: .init())
        XCTAssertFalse(try handoff.ready(for: "a"))
        XCTAssertFalse(io.events.contains("play"))
        XCTAssertTrue(try handoff.ready(for: "b"))
    }

    func testMuteSetterFailureKeepsPlaybackGatedAndDoesNotReleaseSource() throws {
        let io = Endpoints(), handoff = io.make()
        try handoff.prepare(outputUID: "speakers", followsSystem: true, settings: .init())
        io.rejectMute = true
        XCTAssertThrowsError(try handoff.ready(for: "speakers"))
        XCTAssertFalse(io.events.contains("play")); XCTAssertFalse(io.events.contains("release"))
    }

    func testPlaybackFailureRetainsGuardAndStopsConsumerBeforeDiscard() throws {
        let io = Endpoints(), handoff = io.make()
        try handoff.prepare(outputUID: "headphones", followsSystem: false, settings: .init())
        try handoff.fail()
        XCTAssertFalse(io.events.contains("direct")); XCTAssertFalse(io.events.contains("release"))
        XCTAssertEqual(Array(io.events.suffix(2)), ["stop", "discard"])
    }

    func testPrimaryMuteFailureUsesFallbackGuardBeforeReportingMutedPreparation() throws {
        var events: [String] = []
        let handoff = SoundOutputHandoff(setSourceMuted: { muted in
            if muted { events.append("primary-failed"); throw SoundFailure.system(-1) }
        }, setPlaybackEnabled: { events.append($0 ? "play" : "gate") },
        releaseSource: { events.append("release") }, stopPlayback: {}, discardQueued: {},
        fallbackSourceGuard: { events.append("fallback-guard") })
        try handoff.prepare(outputUID: "speakers", followsSystem: true, settings: .init())
        var muted = SoundChannelSettings(); muted.muted = true
        try handoff.reconcile(outputUID: "speakers", followsSystem: true, settings: muted)
        XCTAssertTrue(handoff.sourceGuarded)
        XCTAssertEqual(Array(events.suffix(3)), ["primary-failed", "gate", "fallback-guard"])
        XCTAssertFalse(events.contains("play"))
    }

    func testPrimaryAndFallbackMuteFailuresNeverClaimSourceGuard() throws {
        var enabled = false
        let handoff = SoundOutputHandoff(setSourceMuted: { muted in
            if muted { throw SoundFailure.system(-1) }
        }, setPlaybackEnabled: { enabled = $0 }, releaseSource: {}, stopPlayback: {}, discardQueued: {},
        fallbackSourceGuard: { throw SoundFailure.system(-2) })
        try handoff.prepare(outputUID: "speakers", followsSystem: true, settings: .init())
        var muted = SoundChannelSettings(); muted.muted = true
        XCTAssertThrowsError(try handoff.reconcile(outputUID: "speakers", followsSystem: true, settings: muted))
        XCTAssertFalse(enabled); XCTAssertFalse(handoff.sourceGuarded)
    }

    func testFailureStillStopsConsumerBeforeDiscardWhenGuardSetterThrows() throws {
        let io = Endpoints(), handoff = io.make()
        try handoff.prepare(outputUID: "speakers", followsSystem: true, settings: .init())
        io.rejectMute = true
        XCTAssertThrowsError(try handoff.fail())
        XCTAssertEqual(Array(io.events.suffix(2)), ["stop", "discard"])
        XCTAssertFalse(io.events.contains("release")); XCTAssertFalse(io.events.contains("play"))
    }

    func testBypassGatesThenReleasesGuardBeforeSlowPlaybackTeardown() throws {
        let io = Endpoints(), handoff = io.make()
        try handoff.prepare(outputUID: "speakers", followsSystem: true, settings: .init())
        XCTAssertTrue(try handoff.ready(for: "speakers"))
        io.events.removeAll()
        handoff.stop()
        XCTAssertEqual(io.events, ["gate", "release", "stop", "discard"])
        XCTAssertFalse(try handoff.ready(for: "speakers"), "Late readiness cannot restart a stopped stream")
    }
}
