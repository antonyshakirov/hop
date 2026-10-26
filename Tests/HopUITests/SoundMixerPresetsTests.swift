import HopCore
import XCTest
@testable import Hop

@MainActor
final class SoundMixerPresetsTests: XCTestCase {
    private final class Session: SoundMixingSession {
        var stops = 0
        var configurations: [String: SoundChannelSettings] = [:]
        var destinations: [String: String] = [:]
        func outputs(_ channels: [SoundMixerChannel]) { channels.forEach(configure) }
        func configure(_ channel: SoundMixerChannel) {
            configurations[channel.id] = channel.settings
            destinations[channel.id] = channel.preference.outputUID
        }
        func stop() { stops += 1 }
    }

    func testOfflineAdditionPersistsDestinationWithoutStartingMixer() throws {
        let suite = "HopTests.MixerPresets." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var sessions = 0
        let make = { SoundMixerController(defaults: defaults, makeSession: { _ in sessions += 1; return Session() },
            discover: { [] }, outputs: { [SoundDevice(uid: "headphones", name: "Headphones")] }) }
        let mixer = make()
        mixer.addApplication(id: "org.telegram.desktop", name: "Telegram")
        let app = try XCTUnwrap(mixer.apps.first)
        XCTAssertEqual(app.id, "org.telegram.desktop")
        XCTAssertFalse(app.appRunning); XCTAssertTrue(app.processes.isEmpty)
        XCTAssertTrue(app.preference.pinned)
        mixer.selectOutput(app, uid: "headphones")
        XCTAssertTrue(mixer.hasCustomApplicationAudio)
        XCTAssertFalse(mixer.requested); XCTAssertFalse(mixer.running); XCTAssertEqual(sessions, 0)
        let restored = make()
        restored.open(); defer { restored.close() }
        let next = try XCTUnwrap(restored.apps.first)
        XCTAssertEqual(next.name, "Telegram")
        XCTAssertEqual(next.preference.outputUID, "headphones")
        XCTAssertEqual(next.preference.outputName, "Headphones")
        XCTAssertTrue(next.preference.pinned)
    }

    func testResetClearsOfflineAudioRetainingPinsNamesAndOrder() throws {
        let suite = "HopTests.MixerPresets." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var archived = SoundChannelSettings(); archived.gain = 0.2; archived.muted = true
        defaults.set(try JSONEncoder().encode(["app:archived": archived]), forKey: "soundMixerChannels")
        let session = Session()
        let make = { SoundMixerController(defaults: defaults, makeSession: { _ in session }, discover: { [] },
            outputs: { [SoundDevice(uid: "headphones", name: "Headphones")] }) }
        let mixer = make()
        mixer.addApplication(id: "telegram", name: "Telegram")
        mixer.addApplication(id: "music", name: "Music")
        let telegram = try XCTUnwrap(mixer.apps.first { $0.id == "telegram" })
        mixer.update(telegram) { $0.gain = 0.3; $0.muted = true }
        mixer.selectOutput(telegram, uid: "headphones")
        let order = mixer.apps.map(\.id), preferences = mixer.apps.map(\.preference)
        mixer.start(); defer { mixer.stop(); mixer.close() }
        mixer.resetApplicationAudio()
        XCTAssertTrue(mixer.running); XCTAssertFalse(mixer.hasCustomApplicationAudio)
        XCTAssertEqual(mixer.apps.map(\.id), order)
        for (app, preference) in zip(mixer.apps, preferences) {
            XCTAssertEqual(app.settings, .init())
            XCTAssertEqual(app.preference.name, preference.name)
            XCTAssertEqual(app.preference.pinned, preference.pinned)
            XCTAssertEqual(app.preference.order, preference.order)
            XCTAssertNil(app.preference.outputUID); XCTAssertNil(app.preference.outputName)
            XCTAssertEqual(session.configurations[app.id], .init())
            XCTAssertNil(session.destinations[app.id])
        }
        let saved = try JSONDecoder().decode([String: SoundChannelSettings].self,
            from: XCTUnwrap(defaults.data(forKey: "soundMixerChannels")))
        XCTAssertFalse(saved.values.contains { $0.gain != 1 || $0.muted })
        let restored = make(); restored.open(); defer { restored.close() }
        XCTAssertFalse(restored.hasCustomApplicationAudio)
        XCTAssertEqual(restored.apps.map(\.id), order)
    }

    func testStopAndRestartRestoresOfflinePreset() throws {
        let suite = "HopTests.MixerPresets." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var sessions: [Session] = []
        let mixer = SoundMixerController(defaults: defaults, makeSession: { _ in
            let session = Session(); sessions.append(session); return session
        }, discover: { [] }, outputs: { [SoundDevice(uid: "headphones", name: "Headphones")] })
        mixer.addApplication(id: "telegram", name: "Telegram")
        let app = try XCTUnwrap(mixer.apps.first)
        mixer.update(app) { $0.gain = 0.4; $0.muted = true }
        mixer.selectOutput(app, uid: "headphones")
        mixer.start(); mixer.stop()
        XCTAssertEqual(sessions[0].stops, 1)
        XCTAssertFalse(mixer.requested); XCTAssertTrue(mixer.hasCustomApplicationAudio)
        mixer.start(); defer { mixer.stop(); mixer.close() }
        XCTAssertEqual(sessions[1].configurations[app.id]?.gain, 0.4)
        XCTAssertEqual(sessions[1].configurations[app.id]?.muted, true)
        XCTAssertEqual(sessions[1].destinations[app.id], "headphones")
    }

    func testFreshControllerAndSessionRestoreAudioPinsAndReorderedOfflineList() throws {
        let suite = "HopTests.MixerPresets." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var sessions: [Session] = []
        let make = { SoundMixerController(defaults: defaults, makeSession: { _ in
            let session = Session(); sessions.append(session); return session
        }, discover: { [] }, outputs: { [SoundDevice(uid: "headphones", name: "Headphones")] }) }
        let first = make()
        first.addApplication(id: "music", name: "Music")
        first.addApplication(id: "telegram", name: "Telegram")
        let telegram = try XCTUnwrap(first.apps.first { $0.id == "telegram" })
        first.update(telegram) { $0.gain = 0.3; $0.muted = true }
        first.selectOutput(telegram, uid: "headphones")
        XCTAssertTrue(first.canMove(telegram, by: -1))
        first.move(telegram, by: -1)
        XCTAssertEqual(first.apps.map(\.id), ["telegram", "music"])
        let preferences = first.apps.map(\.preference)
        let settings = first.apps.map(\.settings)
        first.start(); first.suspend(); first.close()
        XCTAssertEqual(sessions.count, 1); XCTAssertEqual(sessions[0].stops, 1)
        let restored = make()
        restored.resumeIfEnabled()
        defer { restored.stop(); restored.close() }
        XCTAssertEqual(sessions.count, 2)
        XCTAssertFalse(sessions[0] === sessions[1])
        XCTAssertTrue(restored.running)
        XCTAssertEqual(restored.apps.map(\.id), ["telegram", "music"])
        XCTAssertEqual(restored.apps.map(\.preference), preferences)
        XCTAssertEqual(restored.apps.map(\.settings), settings)
        XCTAssertTrue(restored.apps.allSatisfy { $0.preference.pinned && !$0.appRunning && $0.processes.isEmpty })
        XCTAssertEqual(sessions[1].configurations["telegram"]?.gain, 0.3)
        XCTAssertEqual(sessions[1].configurations["telegram"]?.muted, true)
        XCTAssertEqual(sessions[1].destinations["telegram"], "headphones")
        XCTAssertEqual(sessions[1].configurations["music"], .init())
        XCTAssertNil(sessions[1].destinations["music"])
    }
}
