import CoreAudio
import HopCore
import XCTest
@testable import Hop

@MainActor
final class SoundApplicationListTests: XCTestCase {
    private final class Session: SoundMixingSession {
        var configured: [String] = []
        func outputs(_ channels: [SoundMixerChannel]) {}
        func configure(_ channel: SoundMixerChannel) { configured.append(channel.id) }
        func stop() {}
    }
    func testPinOrderDestinationAndGainSurviveNewPIDAndOfflineApp() throws {
        let suite = "HopTests.AppList." + UUID().uuidString, session = Session()
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var discovered = [SoundMixerAppSnapshot(id: "browser", name: "Browser", processes: [1], appRunning: true, sourceRunning: true),
                          SoundMixerAppSnapshot(id: "zoom", name: "Zoom", processes: [2], appRunning: true, sourceRunning: true)]
        let outputs = [SoundDevice(uid: "usb", name: "USB")]
        let mixer = SoundMixerController(defaults: defaults, makeSession: { _ in session }, discover: { discovered }, outputs: { outputs })
        mixer.open(); mixer.start()
        let browser = try XCTUnwrap(mixer.apps.first { $0.id == "browser" })
        let zoom = try XCTUnwrap(mixer.apps.first { $0.id == "zoom" })
        mixer.update(browser) { $0.gain = 0.25; $0.muted = true }
        mixer.togglePin(browser); mixer.togglePin(zoom); mixer.move(zoom, by: -1)
        mixer.selectOutput(browser, uid: "usb")
        XCTAssertEqual(mixer.apps.map(\.id), ["zoom", "browser"])
        mixer.close(); mixer.suspend()
        discovered = [SoundMixerAppSnapshot(id: "browser", name: "Browser", processes: [91], appRunning: true, sourceRunning: true)]
        let restored = SoundMixerController(defaults: defaults, makeSession: { _ in Session() }, discover: { discovered }, outputs: { outputs })
        restored.open()
        defer { restored.stop(); restored.close() }
        XCTAssertEqual(restored.apps.map(\.id), ["zoom", "browser"])
        let offline = try XCTUnwrap(restored.apps.first { $0.id == "zoom" })
        XCTAssertFalse(offline.appRunning); XCTAssertTrue(offline.processes.isEmpty)
        let app = try XCTUnwrap(restored.apps.first { $0.id == "browser" })
        XCTAssertEqual(app.processes, [91]); XCTAssertEqual(app.settings.gain, 0.25); XCTAssertTrue(app.settings.muted)
        XCTAssertEqual(app.preference.outputUID, "usb"); XCTAssertEqual(app.preference.outputName, "USB")
    }
    func testActivityRefreshDoesNotReorderRowsAndUnknownIconHasFallback() throws {
        let suite = "HopTests.AppList." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var discovered = [SoundMixerAppSnapshot(id: "b", name: "Same", processes: [2], appRunning: true, sourceRunning: true),
                          SoundMixerAppSnapshot(id: "a", name: "Same", processes: [1], appRunning: true, sourceRunning: true)]
        let mixer = SoundMixerController(defaults: defaults, makeSession: { _ in Session() }, discover: { discovered }, outputs: { [] })
        mixer.open(); defer { mixer.stop(); mixer.close() }
        XCTAssertEqual(mixer.apps.map(\.id), ["a", "b"])
        let a = try XCTUnwrap(mixer.apps.first)
        XCTAssertNil(a.icon)
        mixer.move(a, by: 1)
        let revision = mixer.sourceRevision
        discovered[1].processes = [91]; mixer.open()
        XCTAssertGreaterThan(mixer.sourceRevision, revision)
        discovered[0].sourceRunning = false; mixer.open()
        XCTAssertEqual(mixer.apps.map(\.id), ["b", "a"])
    }
}
