import CoreAudio
import HopCore
import XCTest
@testable import Hop

@available(macOS 14.2, *)
@MainActor
final class SoundRoutingHandoffTests: XCTestCase {
    private final class Stream: SoundAppOutputStream, @unchecked Sendable {
        var outputUID: String?
        var sourcePeak: Float = 0
        var requestedUID: String?
        var followsSystem = true
        var settings = SoundChannelSettings()
        var stopped = false
        var sourceGuarded = true
        var preparingOutput: Bool { requestedUID != outputUID }
        var ready: CheckedContinuation<Void, Error>?
        var waiting = false
        var blockReadiness = false
        var rejectGuard = false
        var rejectActivation = false
        var rejectOutput = false
        func configure(_ settings: SoundChannelSettings) { self.settings = settings }
        func setOutput(_ uid: String?) throws { try setOutput(uid, followsSystem: true) }
        func setOutput(_ uid: String?, followsSystem: Bool) throws {
            if rejectOutput, uid != nil { throw SoundFailure.system(-1) }
            requestedUID = uid; self.followsSystem = followsSystem
            if !followsSystem || uid == nil || settings.muted || settings.gain == 0 { sourceGuarded = true }
            if uid == nil { outputUID = nil }
        }
        func waitUntilOutputReady() async throws {
            waiting = true
            if blockReadiness { try await withCheckedThrowingContinuation { ready = $0 } }
            if rejectGuard { throw SoundFailure.system(-1) }
            sourceGuarded = true
        }
        func activateOutput() throws {
            if rejectActivation { throw SoundFailure.missingDevice }
            outputUID = requestedUID
        }
        func stop() { stopped = true; outputUID = nil; sourceGuarded = false }
    }
    private func settle() async { for _ in 0..<30 { await Task.yield() } }
    private func channel() -> SoundMixerChannel {
        let channel = SoundMixerChannel(id: "app", name: "App", input: false, settings: .init())
        channel.processes = [1]
        return channel
    }

    func testPendingStreamReconcilesMuteAndExplicitDestinationBeforeReadiness() async {
        let stream = Stream(), app = channel()
        stream.blockReadiness = true; stream.sourceGuarded = false
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "a", name: "A"), SoundDevice(uid: "b", name: "B")] },
            systemUID: { "a" }, makeStream: { _, _, _ in stream })
        session.outputs([app]); await settle()
        XCTAssertTrue(stream.waiting)
        app.settings.muted = true; app.preference.outputUID = "b"
        session.configure(app)
        XCTAssertTrue(stream.settings.muted); XCTAssertEqual(stream.requestedUID, "b")
        XCTAssertFalse(stream.followsSystem); XCTAssertTrue(stream.sourceGuarded)
        XCTAssertNil(stream.outputUID)
        stream.ready?.resume(); await settle()
        XCTAssertEqual(stream.outputUID, "b"); XCTAssertEqual(app.routeState, .playing("b"))
        session.stop()
    }

    func testPendingDeviceLossReconcilesBeforeReadiness() async {
        let stream = Stream(), app = channel()
        stream.blockReadiness = true; stream.sourceGuarded = false
        var devices = [SoundDevice(uid: "a", name: "A")]
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { devices },
            systemUID: { "a" }, makeStream: { _, _, _ in stream })
        session.outputs([app]); await settle()
        devices = []; session.outputs([app])
        XCTAssertNil(stream.requestedUID); XCTAssertTrue(stream.sourceGuarded)
        stream.ready?.resume(); await settle()
        XCTAssertNil(stream.outputUID); XCTAssertEqual(app.routeState, .waiting)
        session.stop()
    }

    func testStoppedPendingReadinessCannotActivateOutput() async {
        let stream = Stream(), app = channel()
        stream.blockReadiness = true
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "a", name: "A")] }, systemUID: { "a" },
            makeStream: { _, _, _ in stream })
        session.outputs([app]); await settle(); session.stop()
        XCTAssertTrue(stream.stopped)
        stream.ready?.resume(); await settle()
        XCTAssertNil(stream.outputUID); XCTAssertEqual(app.routeState, .stopped)
    }

    func testRetainedFailedStreamCanRecoverThroughItsConfigurationCallback() async {
        let stream = Stream(), app = channel()
        stream.rejectOutput = true
        var changed: (@Sendable () -> Void)?
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "a", name: "A")] }, systemUID: { "a" },
            makeStream: { _, _, callback in changed = callback; return stream })
        session.outputs([app]); await settle()
        XCTAssertFalse(stream.stopped); XCTAssertTrue(stream.sourceGuarded)
        XCTAssertNil(stream.outputUID)
        stream.rejectOutput = false; changed?(); await settle()
        XCTAssertEqual(stream.outputUID, "a")
        XCTAssertEqual(app.routeState, .playing("a"))
        session.stop()
    }

    func testSuccessfulReplacementRemovesOldBlockedActivationTask() async {
        let old = Stream(), replacement = Stream(), app = channel()
        var builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "a", name: "A"), SoundDevice(uid: "b", name: "B")] }, systemUID: { "a" },
            makeStream: { _, _, _ in builds += 1; return builds == 1 ? old : replacement })
        session.outputs([app]); await settle()
        old.blockReadiness = true; app.preference.outputUID = "b"
        session.configure(app); await settle()
        XCTAssertNotNil(old.ready)
        app.processes = [1, 2]; session.outputs([app]); await settle()
        XCTAssertEqual(replacement.outputUID, "b"); XCTAssertTrue(old.stopped)
        app.preference.outputUID = "a"; session.configure(app); await settle()
        XCTAssertEqual(replacement.outputUID, "a")
        old.ready?.resume(); await settle()
        XCTAssertEqual(replacement.outputUID, "a")
        session.stop()
    }

    func testReplacementActivationFailureRestoresPreviousDestination() async {
        let old = Stream(), replacement = Stream(), app = channel()
        replacement.rejectActivation = true
        var builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "a", name: "A")] }, systemUID: { "a" },
            makeStream: { _, _, _ in builds += 1; return builds == 1 ? old : replacement })
        session.outputs([app]); await settle()
        XCTAssertEqual(old.outputUID, "a")
        app.processes = [1, 2]; session.outputs([app]); await settle()
        XCTAssertFalse(old.stopped); XCTAssertTrue(old.sourceGuarded)
        XCTAssertEqual(old.outputUID, "a")
        XCTAssertTrue(replacement.stopped)
        session.stop()
    }

    func testReplacementGuardFailureRetainsPreviousStream() async {
        let old = Stream(), replacement = Stream(), app = channel()
        replacement.blockReadiness = true; replacement.rejectGuard = true
        var builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "a", name: "A")] }, systemUID: { "a" },
            makeStream: { _, _, _ in builds += 1; return builds == 1 ? old : replacement })
        session.outputs([app]); await settle()
        XCTAssertEqual(old.outputUID, "a")
        app.processes = [1, 2]; session.outputs([app]); await settle()
        XCTAssertTrue(replacement.waiting); XCTAssertFalse(old.stopped)
        replacement.ready?.resume(); await settle()
        XCTAssertFalse(old.stopped); XCTAssertTrue(old.sourceGuarded)
        XCTAssertEqual(old.outputUID, "a"); XCTAssertTrue(replacement.stopped)
        session.stop()
    }
}
