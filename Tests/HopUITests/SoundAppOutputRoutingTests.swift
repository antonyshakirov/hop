import CoreAudio
import HopCore
import XCTest
@testable import Hop

@available(macOS 14.2, *)
@MainActor
final class SoundAppOutputRoutingTests: XCTestCase {
    private final class Stream: SoundAppOutputStream, @unchecked Sendable {
        var outputUID: String?
        var sourcePeak: Float = 0.2
        var stopped = false
        var settings = SoundChannelSettings()
        var outputs: [String?] = []
        var reject = false
        func setOutput(_ uid: String?) throws {
            outputs.append(uid)
            if reject, uid != nil { throw SoundFailure.system(-1) }
            outputUID = uid
        }
        func configure(_ settings: SoundChannelSettings) { self.settings = settings }
        func stop() { stopped = true; outputUID = nil }
    }
    private final class GuardedStream: SoundAppOutputStream, @unchecked Sendable {
        var outputUID: String?
        var sourcePeak: Float = 0
        var events: [String] = []
        private var requestedUID: String?
        private var initialized = false
        private var settings = SoundChannelSettings()
        private lazy var handoff = SoundOutputHandoff(setSourceMuted: { [unowned self] in
            events.append($0 ? "guard" : "direct")
        }, setPlaybackEnabled: { [unowned self] in events.append($0 ? "play" : "gate") },
        releaseSource: { [unowned self] in events.append("release") }, stopPlayback: {}, discardQueued: {})
        var sourceGuarded: Bool { handoff.sourceGuarded }
        var preparingOutput: Bool { requestedUID != outputUID }
        func configure(_ settings: SoundChannelSettings) { self.settings = settings }
        func setOutput(_ uid: String?) throws {
            guard !initialized || requestedUID != uid else { return }
            try handoff.prepare(outputUID: uid, followsSystem: false, settings: settings)
            initialized = true; requestedUID = uid; outputUID = nil
        }
        func activateOutput() throws {
            if let uid = requestedUID, try handoff.ready(for: uid) { outputUID = uid }
        }
        func stop() { handoff.stop(); outputUID = nil }
    }
    private func settle() async { for _ in 0..<20 { await Task.yield() } }
    private func app(_ uid: String? = nil, processes: [AudioObjectID] = [1]) -> SoundMixerChannel {
        let channel = SoundMixerChannel(id: "browser", name: "Browser", input: false, settings: .init())
        channel.processes = processes; channel.preference.outputUID = uid
        return channel
    }
    func testMissingExplicitOutputRetainsSourceGuardAndReturnsOnlyToSameDevice() async {
        var devices = [SoundDevice(uid: "speakers", name: "Speakers"), SoundDevice(uid: "headphones", name: "Headphones")]
        var defaultUID = "speakers"
        let stream = Stream(), channel = app("headphones")
        let session = SoundRoutingSession(failed: { _ in XCTFail("Device loss must not suspend and release a guarded source") },
            devices: { devices }, systemUID: { defaultUID }, makeStream: { _, _, _ in stream })
        session.outputs([channel]); await settle()
        XCTAssertEqual(stream.outputUID, "headphones")
        XCTAssertEqual(channel.routeState, .playing("headphones"))
        devices.removeAll { $0.uid == "headphones" }; defaultUID = "speakers"
        session.outputs([channel])
        XCTAssertNil(stream.outputUID); XCTAssertFalse(stream.stopped)
        XCTAssertEqual(channel.routeState, .waiting)
        defaultUID = "usb"; devices.append(SoundDevice(uid: "usb", name: "USB"))
        session.outputs([channel]); XCTAssertNil(stream.outputUID)
        devices.append(SoundDevice(uid: "headphones", name: "Headphones"))
        channel.settings.gain = 0.25; channel.settings.muted = true
        session.outputs([channel])
        XCTAssertEqual(stream.outputUID, "headphones")
        XCTAssertEqual(stream.settings.gain, 0.25); XCTAssertTrue(stream.settings.muted)
        session.stop(); XCTAssertTrue(stream.stopped)
    }
    func testFollowingDefaultReconcilesWithoutRebuildingCapture() async {
        let stream = Stream(), channel = app()
        var defaultUID = "speakers", created = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "speakers", name: "Speakers"), SoundDevice(uid: "usb", name: "USB")] },
            systemUID: { defaultUID }, makeStream: { _, _, _ in created += 1; return stream })
        session.outputs([channel]); await settle()
        XCTAssertEqual(stream.outputUID, "speakers")
        defaultUID = "usb"; session.outputs([channel]); await settle()
        XCTAssertEqual(stream.outputUID, "usb"); XCTAssertEqual(created, 1)
        session.stop()
    }
    func testRouteFailureKeepsGuardAndNeverReportsRequestedAsPlaying() async {
        let stream = Stream(), channel = app("usb")
        stream.reject = true
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "usb", name: "USB")] }, systemUID: { "usb" }, makeStream: { _, _, _ in stream })
        session.outputs([channel]); await settle()
        XCTAssertNil(stream.outputUID); XCTAssertFalse(stream.stopped)
        XCTAssertEqual(channel.routeState, .failed)
        stream.reject = false; session.configure(channel)
        XCTAssertEqual(channel.routeState, .playing("usb"))
        session.stop()
    }
    func testPendingBuildUsesLatestDestinationAndGain() async {
        var complete: CheckedContinuation<any SoundAppOutputStream, Error>?
        let channel = app("a"), stream = Stream()
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { [SoundDevice(uid: "a", name: "A"), SoundDevice(uid: "b", name: "B")] }, systemUID: { "a" },
            makeStream: { _, _, _ in try await withCheckedThrowingContinuation { complete = $0 } })
        session.outputs([channel]); await settle()
        channel.preference.outputUID = "b"; channel.settings.gain = 0.1
        session.configure(channel)
        complete?.resume(returning: stream); await settle()
        XCTAssertEqual(stream.outputUID, "b"); XCTAssertEqual(stream.settings.gain, 0.1)
        XCTAssertFalse(stream.outputs.contains { $0 == "a" })
        session.stop()
    }
    func testStopRejectsLateBuildAndConfigurationCallback() async {
        var complete: CheckedContinuation<any SoundAppOutputStream, Error>?
        var changed: (@Sendable () -> Void)?
        let stream = Stream(), channel = app("a")
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { [SoundDevice(uid: "a", name: "A")] }, systemUID: { "a" },
            makeStream: { _, _, callback in changed = callback; return try await withCheckedThrowingContinuation { complete = $0 } })
        session.outputs([channel]); await settle(); session.stop()
        complete?.resume(returning: stream); await settle(); changed?(); await settle()
        XCTAssertTrue(stream.stopped); XCTAssertNil(stream.outputUID)
        XCTAssertEqual(channel.routeState, .stopped)
    }
    func testProcessReplacementKeepsOldGuardUntilReplacementReadyOrFailed() async {
        let old = Stream(), next = Stream(), channel = app("missing")
        var complete: CheckedContinuation<any SoundAppOutputStream, Error>?
        var count = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail("Do not release existing guards") }, devices: { [] }, systemUID: { "speakers" },
            makeStream: { _, _, _ in
                count += 1
                if count == 1 { return old }
                return try await withCheckedThrowingContinuation { complete = $0 }
            })
        session.outputs([channel]); await settle()
        channel.processes = [1, 2]; session.outputs([channel]); await settle()
        XCTAssertFalse(old.stopped)
        complete?.resume(throwing: SoundFailure.system(-1)); await settle()
        XCTAssertFalse(old.stopped)
        session.outputs([channel]); await settle()
        complete?.resume(returning: next); await settle()
        XCTAssertTrue(old.stopped); XCTAssertFalse(next.stopped); XCTAssertNil(next.outputUID)
        session.stop(); XCTAssertTrue(next.stopped)
    }

    func testExplicitDeviceLossDrivesRealHandoffGateUntilSameUIDReturns() async {
        let stream = GuardedStream(), channel = app("headphones")
        var devices = [SoundDevice(uid: "speakers", name: "Speakers"), SoundDevice(uid: "headphones", name: "Headphones")]
        var defaultUID = "speakers", builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { devices },
            systemUID: { defaultUID }, makeStream: { _, _, _ in builds += 1; return stream })
        session.outputs([channel]); await settle()
        XCTAssertEqual(stream.outputUID, "headphones"); XCTAssertTrue(stream.sourceGuarded)
        stream.events = []
        devices.removeAll { $0.uid == "headphones" }; session.outputs([channel])
        XCTAssertEqual(stream.events.first, "gate")
        XCTAssertNil(stream.outputUID); XCTAssertTrue(stream.sourceGuarded)
        XCTAssertEqual(channel.routeState, .waiting)
        devices.append(SoundDevice(uid: "usb", name: "USB")); defaultUID = "usb"
        session.outputs([channel]); await settle()
        XCTAssertNil(stream.outputUID)
        XCTAssertFalse(stream.events.contains("play"))
        XCTAssertFalse(stream.events.contains("direct"))
        XCTAssertFalse(stream.events.contains("release"))
        XCTAssertEqual(channel.preference.outputUID, "headphones")
        devices.append(SoundDevice(uid: "headphones", name: "Headphones"))
        session.outputs([channel]); await settle()
        XCTAssertEqual(stream.outputUID, "headphones")
        XCTAssertEqual(channel.routeState, .playing("headphones"))
        XCTAssertEqual(stream.events.last, "play")
        XCTAssertEqual(builds, 1)
        session.stop()
    }

}
