import CoreAudio
import HopCore
import XCTest
@testable import Hop

@available(macOS 14.2, *)
@MainActor
final class SoundListeningMasterTests: XCTestCase {
    private final class Stream: SoundAppOutputStream, @unchecked Sendable {
        var outputUID: String?
        var sourcePeak: Float = 0
        var requestedUID: String?
        var settings = SoundChannelSettings()
        var firstAudible: SoundChannelSettings?
        var ready: CheckedContinuation<Void, Error>?
        var blockReadiness = false
        var configurations = 0
        var gates = 0
        var events: [String] = []
        private let boundary = SoundOutputConfigurationBoundary()
        var preparingOutput: Bool { outputUID != requestedUID }
        func configure(_ settings: SoundChannelSettings) { self.settings = settings; configurations += 1; events.append("gain") }
        func update(_ settings: SoundChannelSettings, outputUID: String?, followsSystem: Bool, masterUID: String?) throws {
            try boundary.apply(outputUID: outputUID, masterUID: masterUID,
                gate: { self.gates += 1; self.events.append("gate") }) {
                configure(settings); try setOutput(outputUID)
            }
        }
        func setOutput(_ uid: String?) throws { requestedUID = uid; if uid == nil { outputUID = nil } }
        func waitUntilOutputReady() async throws {
            if blockReadiness { try await withCheckedThrowingContinuation { ready = $0 } }
        }
        func activateOutput() throws { firstAudible = settings; outputUID = requestedUID }
        func stop() { outputUID = nil }
    }

    private func settle() async { for _ in 0..<30 { await Task.yield() } }
    private func app(output: String? = "other", gain: Double = 0.5) -> SoundMixerChannel {
        let app = SoundMixerChannel(id: "app", name: "App", input: false, settings: .init())
        app.processes = [1]; app.preference.outputUID = output; app.settings.gain = gain
        return app
    }
    private func devices(volume: Double = 0.25, muted: Bool = false) -> [SoundDevice] {
        [SoundDevice(uid: "mac", name: "Mac", volume: volume, muted: muted),
         SoundDevice(uid: "other", name: "Other", volume: 0.8, muted: false)]
    }

    func testOtherDestinationReceivesMacAttenuationWithoutChangingStoredOrDeviceGain() async {
        let stream = Stream(), app = app(), hardware = devices()
        let saved = app.settings
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { hardware },
            systemUID: { "mac" }, makeStream: { _, _, _ in stream })
        session.outputs([app]); await settle()
        XCTAssertEqual(stream.settings.gain, 0.125, accuracy: 0.000001)
        XCTAssertEqual(stream.firstAudible?.gain ?? -1, 0.125, accuracy: 0.000001)
        XCTAssertEqual(stream.outputUID, "other")
        XCTAssertEqual(app.settings, saved)
        XCTAssertEqual(hardware.last?.volume, 0.8)
        session.stop()
    }

    func testDefaultAndExplicitSameDestinationApplyHardwareMasterOnlyOnce() async {
        for output in [nil, "mac"] as [String?] {
            let stream = Stream(), app = app(output: output)
            let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { self.devices() },
                systemUID: { "mac" }, makeStream: { _, _, _ in stream })
            session.outputs([app]); await settle()
            XCTAssertEqual(stream.settings.gain, 0.5, accuracy: 0.000001)
            XCTAssertEqual(stream.outputUID, "mac")
            session.stop()
        }
    }

    func testMacMuteAppliesToOtherDestinationAndUnmutePreservesSavedAppMute() async {
        let stream = Stream(), app = app()
        var hardware = devices(muted: true)
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { hardware },
            systemUID: { "mac" }, makeStream: { _, _, _ in stream })
        session.outputs([app]); await settle()
        XCTAssertTrue(stream.settings.muted)
        XCTAssertFalse(app.settings.muted)
        hardware = devices(); session.outputs([app])
        XCTAssertFalse(stream.settings.muted)
        app.settings.muted = true; session.configure(app)
        hardware = devices(muted: true); session.outputs([app])
        hardware = devices(); session.outputs([app])
        XCTAssertTrue(stream.settings.muted); XCTAssertTrue(app.settings.muted)
        session.stop()
    }

    func testPendingFirstAudibleFrameUsesLatestMasterAndAppSettings() async {
        let stream = Stream(), app = app(gain: 1)
        stream.blockReadiness = true
        var hardware = devices(volume: 0.8)
        var builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { hardware },
            systemUID: { "mac" }, makeStream: { _, _, _ in builds += 1; return stream })
        session.outputs([app]); await settle()
        XCTAssertNotNil(stream.ready)
        hardware = devices(volume: 0.2, muted: true)
        app.settings.gain = 0.5; session.outputs([app])
        XCTAssertEqual(stream.settings.gain, 0.1, accuracy: 0.000001)
        XCTAssertTrue(stream.settings.muted)
        stream.ready?.resume(); await settle()
        XCTAssertEqual(stream.firstAudible?.gain ?? -1, 0.1, accuracy: 0.000001)
        XCTAssertEqual(stream.firstAudible?.muted, true)
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(app.settings.gain, 0.5)
        XCTAssertFalse(app.settings.muted)
        session.stop()
    }
    private final class Master: SoundListeningMasterSource {
        var value = SoundListeningMasterSnapshot(uid: "mac", scalar: 0.25, muted: false)
        var callback: (() -> Void)?
        var reads = 0
        var starts = 0
        var stops = 0
        func snapshot() -> SoundListeningMasterSnapshot { reads += 1; return value }
        func start(_ changed: @escaping () -> Void) { starts += 1; callback = changed }
        func stop() { stops += 1 }
    }

    func testBackgroundObserverCoalescesLatestLevelWithoutRebuildingOrGating() async {
        let master = Master(), stream = Stream(), app = app()
        var builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { self.devices() },
            makeStream: { _, _, _ in builds += 1; return stream }, master: master)
        session.outputs([app]); await settle()
        let count = stream.configurations
        for level in [0.8, 0.6, 0.2] {
            master.value = .init(uid: "mac", scalar: level, muted: false); master.callback?()
        }
        await settle()
        XCTAssertEqual(stream.configurations, count + 1)
        XCTAssertEqual(stream.settings.gain, 0.1, accuracy: 0.000001)
        XCTAssertEqual(stream.gates, 0); XCTAssertEqual(builds, 1); XCTAssertEqual(master.starts, 1)
        session.stop(); XCTAssertEqual(master.stops, 1)
    }

    func testStopRejectsQueuedAndLateObserverCallbacksAndRestartUsesLatestSnapshot() async {
        let master = Master(), stream = Stream(), app = app()
        var builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { self.devices() },
            makeStream: { _, _, _ in builds += 1; return stream }, master: master)
        session.outputs([app]); await settle()
        let late = master.callback
        master.value = .init(uid: "mac", scalar: 0.1, muted: true); late?()
        session.stop()
        let count = stream.configurations
        late?(); await settle()
        XCTAssertEqual(stream.configurations, count); XCTAssertNil(stream.outputUID)
        XCTAssertEqual(builds, 1)
        session.outputs([app]); await settle()
        XCTAssertEqual(master.starts, 2)
        XCTAssertEqual(stream.settings.gain, 0.05, accuracy: 0.000001)
        XCTAssertTrue(stream.settings.muted)
        let restarted = stream.configurations
        late?(); await settle()
        XCTAssertEqual(stream.configurations, restarted)
        session.stop()
    }

    func testDefaultUIDTransitionGatesBeforeRemovingSoftwareMasterFromExplicitDestination() async {
        let master = Master(), stream = Stream(), app = app()
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { self.devices() },
            makeStream: { _, _, _ in stream }, master: master)
        session.outputs([app]); await settle()
        XCTAssertEqual(stream.settings.gain, 0.125, accuracy: 0.000001)
        stream.events = []
        master.value = .init(uid: "other", scalar: 0.8, muted: false); master.callback?()
        await settle()
        XCTAssertEqual(Array(stream.events.prefix(2)), ["gate", "gain"])
        XCTAssertEqual(stream.settings.gain, 0.5, accuracy: 0.000001)
        XCTAssertEqual(stream.outputUID, "other")
        session.stop()
    }

    func testPendingObserverUpdateUsesLatestMasterAtActivation() async {
        let master = Master(), stream = Stream(), app = app()
        stream.blockReadiness = true
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { self.devices() },
            makeStream: { _, _, _ in stream }, master: master)
        session.outputs([app]); await settle()
        master.value = .init(uid: "mac", scalar: 0.1, muted: true); master.callback?()
        await settle()
        XCTAssertEqual(stream.settings.gain, 0.05, accuracy: 0.000001)
        XCTAssertTrue(stream.settings.muted)
        stream.ready?.resume(); await settle()
        XCTAssertEqual(stream.firstAudible?.gain ?? -1, 0.05, accuracy: 0.000001)
        XCTAssertEqual(stream.firstAudible?.muted, true)
        session.stop()
    }

    func testDBAttenuationUsesAmplitudeRelativeToMaximum() {
        let value = SoundListeningMasterSnapshot(uid: "mac", scalar: 0.25, muted: false,
            decibels: -47.625, maximumDB: 0)
        XCTAssertEqual(value.attenuation, pow(10, -47.625 / 20), accuracy: 0.0000001)
        XCTAssertLessThan(value.attenuation, 0.005)
        XCTAssertEqual(SoundListeningMasterSnapshot(uid: "mac", scalar: 0.8, muted: nil,
            decibels: -16, maximumDB: -6).attenuation, pow(10, -0.5), accuracy: 0.0000001)
    }

    func testZeroScalarStaysZeroEvenWithFiniteDBFloor() {
        XCTAssertEqual(SoundListeningMasterSnapshot(uid: "mac", scalar: 0, muted: false,
            decibels: -60, maximumDB: 0).attenuation, 0)
    }

    func testUnusableMetadataFallsBackToFiniteScalarThenNeutralAndNeverBoosts() {
        XCTAssertEqual(SoundListeningMasterSnapshot(uid: "mac", scalar: 0.3, muted: false,
            decibels: .nan, maximumDB: 0).attenuation, 0.3)
        XCTAssertEqual(SoundListeningMasterSnapshot(uid: "mac", scalar: .infinity, muted: true).attenuation, 1)
        XCTAssertTrue(SoundListeningMasterSnapshot(uid: nil, scalar: nil, muted: true).muted)
        XCTAssertEqual(SoundListeningMasterSnapshot(uid: nil, scalar: nil, muted: nil).attenuation, 1)
        XCTAssertEqual(SoundListeningMasterSnapshot(uid: "mac", scalar: 3, muted: false).attenuation, 1)
        XCTAssertEqual(SoundListeningMasterSnapshot(uid: "mac", scalar: 0.3, muted: false,
            decibels: 6, maximumDB: 0).attenuation, 1)
    }

    func testObserverOwnsOneSubscriptionUntilStopped() {
        var installs = 0, removals = 0
        let observer = SoundListeningMasterObserver(read: { .init(uid: nil, scalar: nil, muted: nil) },
            watch: { _ in installs += 1 }, unwatch: { removals += 1 })
        observer.start {}; observer.start {}
        XCTAssertEqual(installs, 1)
        observer.stop(); observer.stop()
        XCTAssertEqual(removals, 1)
        observer.start {}; observer.stop()
        XCTAssertEqual(installs, 2); XCTAssertEqual(removals, 2)
    }

    func testMissingExplicitDestinationRemainsPausedThenRejoinsAtLatestMaster() async {
        let master = Master(), stream = Stream(), app = app()
        var hardware = [SoundDevice(uid: "mac", name: "Mac")]
        var builds = 0
        let session = SoundRoutingSession(failed: { _ in XCTFail() }, devices: { hardware },
            makeStream: { _, _, _ in builds += 1; return stream }, master: master)
        session.outputs([app]); await settle()
        XCTAssertNil(stream.outputUID); XCTAssertEqual(app.routeState, .waiting)
        master.value = .init(uid: "mac", scalar: 0.1, muted: false); master.callback?()
        await settle()
        XCTAssertNil(stream.outputUID)
        hardware.append(SoundDevice(uid: "other", name: "Other", volume: 0.8))
        session.outputs([app]); await settle()
        XCTAssertEqual(stream.outputUID, "other")
        XCTAssertEqual(stream.firstAudible?.gain ?? -1, 0.05, accuracy: 0.000001)
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(app.preference.outputUID, "other")
        session.stop()
    }

    func testOneMasterRefreshReadsOneSnapshotAndCatalogueForAllApps() async {
        let master = Master()
        var catalogues = 0, builds = 0
        var streams: [Stream] = []
        let apps = (1...4).map { index in
            let channel = SoundMixerChannel(id: "app\(index)", name: "App", input: false, settings: .init())
            channel.processes = [UInt32(index)]; channel.preference.outputUID = "other"
            return channel
        }
        let session = SoundRoutingSession(failed: { _ in XCTFail() },
            devices: { catalogues += 1; return self.devices() },
            makeStream: { _, _, _ in
                builds += 1; let stream = Stream(); streams.append(stream); return stream
            }, master: master)
        session.outputs(apps); await settle()
        XCTAssertEqual(builds, 4)
        let configurations = streams.map(\.configurations)
        master.reads = 0; catalogues = 0
        master.value = .init(uid: "mac", scalar: 0.1, muted: false)
        master.callback?(); await settle()
        XCTAssertEqual(master.reads, 1)
        XCTAssertEqual(catalogues, 1)
        XCTAssertEqual(builds, 4)
        for (index, stream) in streams.enumerated() {
            XCTAssertEqual(stream.settings.gain, 0.1, accuracy: 0.000001)
            XCTAssertEqual(stream.configurations, configurations[index] + 1)
            XCTAssertEqual(stream.gates, 0)
            XCTAssertEqual(stream.outputUID, "other")
        }
        session.stop()
    }

}
