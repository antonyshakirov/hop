import HopCore
import XCTest
@testable import Hop

@MainActor
final class SoundMixerWorkspaceDiscoveryTests: XCTestCase {
    private final class Session: SoundMixingSession {
        func outputs(_ channels: [SoundMixerChannel]) {}
        func configure(_ channel: SoundMixerChannel) {}
        func stop() {}
    }

    func testProcessMetadataCacheKeepsLiveRunningStateAndReloadsReusedPIDs() {
        var cache = SoundProcessMetadataCache(), loads = 0
        let launch = Date(timeIntervalSince1970: 100)
        func load(_ id: String) -> SoundMixerAppSnapshot {
            loads += 1
            return SoundMixerAppSnapshot(id: id, name: id, processes: [], appRunning: true, sourceRunning: false)
        }
        XCTAssertEqual(cache.value(pid: 1, launch: launch, running: true, load: { load("first") })?.id, "first")
        XCTAssertEqual(cache.value(pid: 1, launch: launch, running: false, load: { load("unchanged") })?.appRunning, false)
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(cache.value(pid: 1, launch: launch.addingTimeInterval(1), running: true, load: { load("reused") })?.id, "reused")
        XCTAssertEqual(loads, 2)
        cache.retain([])
        _ = cache.value(pid: 1, launch: launch, running: true, load: { load("reopened") })
        XCTAssertEqual(loads, 3)
        _ = cache.value(pid: 2, launch: nil, running: true, load: { load("unknown") })
        _ = cache.value(pid: 2, launch: nil, running: true, load: { load("unknown") })
        XCTAssertEqual(loads, 5)
    }

    func testOwnerMatchingUsesCompleteBundleSegmentsAndTheExistingRootPreference() {
        let root = SoundMixerAppSnapshot(id: "example.player", name: "Player", processes: [], appRunning: true, sourceRunning: false)
        let child = SoundMixerAppSnapshot(id: "example.player.helper", name: "Helper", processes: [], appRunning: true, sourceRunning: false)
        let unrelated = SoundMixerAppSnapshot(id: "example.player-other", name: "Other", processes: [], appRunning: true, sourceRunning: false)
        let empty = SoundMixerAppSnapshot(id: "", name: "Empty", processes: [], appRunning: true, sourceRunning: false)
        XCTAssertEqual(SoundMixerDiscovery.owningApplication(bundle: "example.player.helper.audio", candidates: [child, unrelated, root, empty])?.id, root.id)
        XCTAssertEqual(SoundMixerDiscovery.owningApplication(bundle: unrelated.id, candidates: [root, unrelated])?.id, unrelated.id)
        XCTAssertNil(SoundMixerDiscovery.owningApplication(bundle: "example.player2.audio", candidates: [root, empty]))
        XCTAssertEqual(SoundMixerDiscovery.owningApplication(bundle: child.id, candidates: [child])?.id, child.id)
    }

    func testRunningAppWithoutAnAudioClientHasNoInventedAudioProcess() throws {
        let telegram = SoundMixerAppSnapshot(id: "org.telegram.desktop", name: "Telegram", processes: [],
            appRunning: true, sourceRunning: false)
        let merged = SoundMixerDiscovery.merging(audio: [], running: [telegram])
        let app = try XCTUnwrap(merged.first { $0.id == telegram.id })
        XCTAssertTrue(app.appRunning); XCTAssertFalse(app.sourceRunning); XCTAssertTrue(app.processes.isEmpty)
    }

    func testWorkspaceEnrichmentRetainsHALOwnershipSourceAndMetadata() throws {
        let icon = URL(fileURLWithPath: "/fixture/Browser.app")
        let audio = SoundMixerAppSnapshot(id: "browser", name: "Browser", processes: [7, 9],
            appRunning: false, sourceRunning: true, iconURL: icon)
        let running = SoundMixerAppSnapshot(id: "browser", name: "Other name", processes: [],
            appRunning: true, sourceRunning: false, iconURL: URL(fileURLWithPath: "/other/Browser.app"))
        let merged = SoundMixerDiscovery.merging(audio: [audio], running: [running])
        XCTAssertEqual(merged.count, 1)
        let app = try XCTUnwrap(merged.first)
        XCTAssertTrue(app.appRunning); XCTAssertTrue(app.sourceRunning)
        XCTAssertEqual(app.processes, [7, 9]); XCTAssertEqual(app.name, "Browser"); XCTAssertEqual(app.iconURL, icon)
    }

    func testWorkspaceOnlySnapshotsExcludeOwnAppsEmptyIDsAndTerminatedApps() {
        let ids = ["com.antonshakirov.hop", "com.antonshakirov.hop.helper", "com.antonshakirov.minimo", ""]
        var running = ids.map { SoundMixerAppSnapshot(id: $0, name: $0, processes: [], appRunning: true, sourceRunning: false) }
        running.append(.init(id: "closed", name: "Closed", processes: [], appRunning: false, sourceRunning: false))
        XCTAssertTrue(SoundMixerDiscovery.merging(audio: [], running: running).isEmpty)
    }

    func testSystemSoundDaemonIsNotAnAppButAppleAppsAndSimilarNamesRemain() {
        let daemonIDs = ["systemsoundserverd", "com.apple.systemsoundserverd"]
        let daemons = daemonIDs.map {
            SoundMixerAppSnapshot(id: $0, name: "systemsoundserverd", processes: [70], appRunning: true, sourceRunning: true)
        }
        let music = SoundMixerAppSnapshot(id: "com.apple.Music", name: "Music", processes: [71], appRunning: true, sourceRunning: true)
        let namedLikeDaemon = SoundMixerAppSnapshot(id: "org.example.sound", name: "systemsoundserverd", processes: [72], appRunning: true, sourceRunning: true)
        let result = SoundMixerDiscovery.merging(audio: daemons + [music, namedLikeDaemon], running: daemons)
        XCTAssertEqual(Set(result.map(\.id)), [music.id, namedLikeDaemon.id])
        XCTAssertEqual(result.first { $0.id == music.id }?.processes, [71])
    }

    func testLegacyPinnedSystemSoundDaemonDoesNotReturnOrKeepCustomAudioActive() throws {
        let suite = "HopTests.WorkspaceDaemon." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = SoundChannelSettings(); settings.gain = 0.25; settings.muted = true
        var preference = SoundAppPreference(name: "systemsoundserverd")
        preference.pinned = true; preference.outputUID = "headphones"
        defaults.set(try JSONEncoder().encode(["app:systemsoundserverd": settings]), forKey: "soundMixerChannels")
        defaults.set(try JSONEncoder().encode(["systemsoundserverd": preference]), forKey: SoundMixerController.preferencesKey)
        let mixer = SoundMixerController(defaults: defaults, makeSession: { _ in Session() }, discover: {
            [.init(id: "systemsoundserverd", name: "systemsoundserverd", processes: [70], appRunning: false, sourceRunning: true)]
        }, outputs: { [] })
        mixer.open(); defer { mixer.close() }
        XCTAssertTrue(mixer.apps.isEmpty)
        XCTAssertFalse(mixer.hasCustomApplicationAudio)
        mixer.addApplication(id: "com.apple.systemsoundserverd", name: "systemsoundserverd")
        XCTAssertTrue(mixer.apps.isEmpty)
    }

    func testPinnedSilentAppReflectsRunningStateWithoutLosingPresetOrAddingUnpinnedApps() throws {
        let suite = "HopTests.WorkspaceDiscovery." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var running = [SoundMixerAppSnapshot(id: "telegram", name: "Telegram", processes: [], appRunning: true, sourceRunning: false),
                       SoundMixerAppSnapshot(id: "other", name: "Other", processes: [], appRunning: true, sourceRunning: false)]
        var sessions = 0
        let mixer = SoundMixerController(defaults: defaults, makeSession: { _ in sessions += 1; return Session() },
            discover: { SoundMixerDiscovery.merging(audio: [], running: running) },
            outputs: { [SoundDevice(uid: "headphones", name: "Headphones")] })
        mixer.addApplication(id: "telegram", name: "Telegram")
        let app = try XCTUnwrap(mixer.apps.first)
        XCTAssertEqual(mixer.apps.map(\.id), ["telegram"])
        XCTAssertTrue(app.appRunning); XCTAssertFalse(app.hasAudio); XCTAssertTrue(app.processes.isEmpty)
        mixer.selectOutput(app, uid: "headphones")
        mixer.update(app) { $0.gain = 0.25; $0.muted = true }
        running = []; mixer.open()
        defer { mixer.close() }
        XCTAssertFalse(app.appRunning)
        XCTAssertTrue(app.preference.pinned); XCTAssertEqual(app.preference.outputUID, "headphones")
        XCTAssertEqual(app.settings.gain, 0.25); XCTAssertTrue(app.settings.muted)
        XCTAssertFalse(mixer.running); XCTAssertEqual(sessions, 0)
    }
}
