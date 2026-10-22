import XCTest
import HopCore
@testable import Hop

@MainActor
final class SoundMixerLifecycleTests: XCTestCase {
    private final class Session: SoundMixingSession {
        var starts = 0
        var stops = 0
        let failed: (SoundFailure) -> Void
        init(_ failed: @escaping (SoundFailure) -> Void) { self.failed = failed }
        func outputs(_ channels: [SoundMixerChannel]) { starts += 1 }
        func configure(_ channel: SoundMixerChannel) {}
        func levels() -> [String: Double] { [:] }
        func stop() { stops += 1 }
    }

    private func settings() -> (String, UserDefaults) {
        let name = "HopTests.OutputMixer." + UUID().uuidString
        return (name, UserDefaults(suiteName: name)!)
    }

    func testChoiceSurvivesClosingAndQuitAndRestoresWithoutInputRouting() throws {
        let (name, defaults) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = Data(#"{"input:mic":{"gain":1.5,"muted":false,"active":true,"bass":true}}"#.utf8)
        defaults.set(legacy, forKey: "soundMixerChannels")
        var sessions: [Session] = []
        let factory: (@escaping (SoundFailure) -> Void) -> SoundMixingSession = {
            let session = Session($0); sessions.append(session); return session
        }
        let first = SoundMixerController(defaults: defaults, makeSession: factory)
        defer { first.stop(); first.close() }
        first.resumeIfEnabled()
        XCTAssertTrue(sessions.isEmpty)
        first.open(); first.start()
        XCTAssertTrue(first.running)
        XCTAssertTrue(defaults.bool(forKey: SoundMixerController.enabledKey))
        first.close()
        XCTAssertTrue(first.running)
        XCTAssertEqual(sessions[0].stops, 0)
        first.open(); first.suspend(); first.close()
        XCTAssertTrue(first.requested)
        XCTAssertFalse(first.running)
        XCTAssertEqual(sessions[0].stops, 1)
        XCTAssertEqual(defaults.data(forKey: "soundMixerChannels"), legacy)
        let restored = SoundMixerController(defaults: defaults, makeSession: factory)
        defer { restored.stop(); restored.close() }
        restored.resumeIfEnabled()
        XCTAssertTrue(restored.running)
        XCTAssertEqual(sessions.count, 2)
        restored.stop()
        let stopped = SoundMixerController(defaults: defaults, makeSession: factory)
        stopped.resumeIfEnabled()
        XCTAssertFalse(stopped.requested)
        XCTAssertFalse(stopped.running)
        XCTAssertEqual(sessions.count, 2)
    }

    func testModuleDisableSuspendsAndExplicitChoiceResumesOnReenable() {
        let (name, defaults) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        var enabled = true, sessions: [Session] = []
        let mixer = SoundMixerController(enabled: { enabled }, defaults: defaults, makeSession: {
            let session = Session($0); sessions.append(session); return session
        })
        defer { mixer.stop(); mixer.close() }
        mixer.start(); enabled = false; mixer.suspend()
        mixer.resumeIfEnabled()
        XCTAssertFalse(mixer.running)
        XCTAssertTrue(mixer.requested)
        enabled = true; mixer.resumeIfEnabled()
        XCTAssertTrue(mixer.running)
        XCTAssertEqual(sessions.count, 2)
    }

    func testFailureRestoresDirectAudioWithoutErasingChoiceAndIgnoresOldCallbacks() {
        let (name, defaults) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        var sessions: [Session] = []
        let mixer = SoundMixerController(defaults: defaults, makeSession: {
            let session = Session($0); sessions.append(session); return session
        })
        defer { mixer.stop(); mixer.close() }
        mixer.start()
        sessions[0].failed(.permission)
        XCTAssertFalse(mixer.running)
        XCTAssertEqual(mixer.failure, .permission)
        XCTAssertEqual(sessions[0].stops, 1)
        XCTAssertTrue(mixer.requested)
        mixer.resumeIfEnabled()
        XCTAssertTrue(mixer.running)
        XCTAssertNil(mixer.failure)
        sessions[0].failed(.system(-1))
        XCTAssertTrue(mixer.running)
        XCTAssertNil(mixer.failure)
    }

    func testAppGainAndMutePersistAndInputEditsCannotStartCapture() throws {
        let (name, defaults) = settings()
        defer { defaults.removePersistentDomain(forName: name) }
        let mixer = SoundMixerController(defaults: defaults, makeSession: { Session($0) })
        defer { mixer.stop(); mixer.close() }
        let app = SoundMixerChannel(id: "browser", name: "Browser", input: false, settings: .init())
        mixer.update(app) { $0.gain = 1.8; $0.muted = true }
        XCTAssertEqual(app.settings.gain, 1)
        let saved = try JSONDecoder().decode([String: SoundChannelSettings].self,
            from: XCTUnwrap(defaults.data(forKey: "soundMixerChannels")))
        XCTAssertEqual(saved["app:browser"]?.gain, 1)
        XCTAssertEqual(saved["app:browser"]?.muted, true)
        let input = SoundMixerChannel(id: "mic", name: "Mic", input: true, settings: .init())
        mixer.update(input) { $0.bass = true; $0.gain = 0 }
        XCTAssertEqual(input.settings, .init())
        XCTAssertFalse(mixer.running)
    }
}
