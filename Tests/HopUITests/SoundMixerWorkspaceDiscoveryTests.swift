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
