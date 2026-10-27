import XCTest
import HopCore
@testable import Hop

@MainActor
final class AgentAudioBridgeTests: XCTestCase {
    private final class Hardware: SoundHardware {
        var volume = 0.6, muted = false
        var output = "fixture-output", input = "fixture-mic"
        var writes = 0
        var additionalInputs: [String] = []
        func devices(_ direction: SoundDirection) -> [SoundDevice] {
            let ids = direction == .input ? [input] + additionalInputs.filter { $0 != input } : [output]
            return ids.map { .init(uid: $0, name: "Synthetic", volume: volume, muted: muted, canChangeVolume: true, canMute: true) }
        }
        func defaultUID(_ direction: SoundDirection) -> String? { direction == .input ? input : output }
        func select(_ uid: String, direction: SoundDirection) throws { writes += 1; if direction == .input { input = uid } else { output = uid } }
        func setVolume(_ value: Double, uid: String, direction: SoundDirection) throws { writes += 1; volume = value }
        func setMute(_ value: Bool, uid: String, direction: SoundDirection) throws { writes += 1; muted = value }
        func watch(_ changed: @escaping () -> Void) {}
        func unwatch() {}
    }
    private final class Meter: SoundMeter {
        var level = 0.0
        var permitted = false
        func requestAccess(_ completion: @escaping (Bool) -> Void) { XCTFail("Agent commands must not start level-meter permissions") }
        func start(_ uid: String, _ interrupted: @escaping () -> Void) throws { XCTFail("Agent commands must not record level-meter samples") }
        func stop() {}
    }
    private final class Session: SoundCallSession {
        var microphoneMuteChanged: ((Bool) -> Void)?
        var starts = 0, updates = 0, stops = 0
        var startACK: ((Result<Void, SoundFailure>) -> Void)?
        var stopACK: ((Result<Void, SoundFailure>) -> Void)?
        var delayStop = false
        var updateACK: ((Result<Void, SoundFailure>) -> Void)?
        func setMicrophoneMuted(_ value: Bool) -> Bool { true }
        func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { starts += 1; startACK = completed }
        func update(_ configuration: SoundCallConfiguration) { updates += 1 }
        func update(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { updates += 1; updateACK = completed }
        func stop() { stops += 1 }
        func stop(completed: @escaping (Result<Void, SoundFailure>) -> Void) {
            stop()
            if delayStop { stopACK = completed } else { completed(.success(())) }
        }
        func shutdown() {}
    }
    private final class Output: SoundMixingSession {
        func outputs(_ channels: [SoundMixerChannel]) {}
        func configure(_ channel: SoundMixerChannel) {}
        func stop() {}
    }
    private final class Access { var asked = 0; var answer: ((Bool) -> Void)? }
    @MainActor
    private final class Fixture {
        let hardware = Hardware(), session = Session(), access = Access()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "HopTests.AgentAudio." + UUID().uuidString
        let defaults: UserDefaults
        let sound: SoundController, mixer: SoundMixerController, call: SoundCallMixController
        let model: AppModel, bridge: AgentBridge
        init() {
            defaults = UserDefaults(suiteName: suite)!
            sound = SoundController(hardware: hardware, meter: Meter(), enabled: { true })
            mixer = SoundMixerController(defaults: defaults, makeSession: { _ in Output() }, discover: {
                [.init(id: "fixture.app", name: "Synthetic", processes: [100], appRunning: true, sourceRunning: true)]
            }, outputs: { [.init(uid: "fixture-output", name: "Synthetic")] })
            let access = access
            call = SoundCallMixController(enabled: true, session: session, access: { access.asked += 1; access.answer = $0 })
            model = AppModel(preview: true, soundController: sound, mixerController: mixer, callController: call, soundEnabled: { true })
            bridge = AgentBridge(directory: root)
        }
        func cleanup() { call.stop(); mixer.stop(); sound.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        func command(_ value: [String: Any]) throws -> AgentAudioCommand {
            let now = Date(), iso = ISO8601DateFormatter()
            let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "id": UUID().uuidString.lowercased(),
                "createdAt": iso.string(from: now.addingTimeInterval(-2)), "expiresAt": iso.string(from: now.addingTimeInterval(100)),
                "confirmation": ["method": "client_agent_attestation", "confirmedAt": iso.string(from: now)], "command": value])
            guard case .audio(let command) = try AgentRequestV2.parse(data, now: now).command else { throw AgentProtocolError("not_audio") }
            return command
        }
        func send(_ value: [String: Any], completed: @escaping (AgentResultV2) -> Void) throws { bridge.performAudio(try command(value), on: model, completed: completed) }
    }
    func testReadStateAndSavingSourcesDoNotAskPermissionOrStartCapture() throws {
        let f = Fixture(); defer { f.cleanup() }
        let state = f.bridge.audioState(f.model)
        XCTAssertEqual((state["inputs"] as? [[String: Any]])?.first?["uid"] as? String, "fixture-mic")
        XCTAssertEqual((state["availableApplications"] as? [[String: Any]])?.first?["appID"] as? String, "fixture.app")
        XCTAssertTrue(f.sound.inputs.isEmpty); XCTAssertTrue(f.mixer.apps.isEmpty)
        try f.send(["do": "audio.inputSource.update", "source": "system", "gain": 0.25, "active": false]) { XCTAssertEqual($0.status, "applied") }
        XCTAssertEqual(f.call.microphone.gain, 0.25); XCTAssertFalse(f.call.microphone.active)
        XCTAssertEqual(f.access.asked, 0); XCTAssertEqual(f.session.starts, 0); XCTAssertEqual(f.hardware.writes, 0)
        XCTAssertFalse(f.sound.windowOpen); XCTAssertFalse(f.call.running)
    }
    func testStartWaitsForRealACKAndIndependentStopCancelsPendingStart() async throws {
        let f = Fixture(); defer { f.cleanup() }
        var result: AgentResultV2?
        let completed = expectation(description: "start completion after ACK")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { result = $0; completed.fulfill() }
        XCTAssertNil(result); XCTAssertEqual(f.access.asked, 1); XCTAssertEqual(f.session.starts, 0)
        f.access.answer?(true)
        XCTAssertEqual(f.session.starts, 1); XCTAssertNil(result); XCTAssertTrue(f.call.effectiveInputUIDs.isEmpty)
        f.session.startACK?(.success(()))
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(result?.status, "applied"); XCTAssertEqual(f.call.effectiveInputUIDs, ["fixture-mic"])
        try f.send(["do": "audio.inputMixer.set", "enabled": false]) { XCTAssertEqual($0.status, "applied") }
        let cancelled = expectation(description: "pending start cancelled")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.code, "audio_input_start_cancelled"); cancelled.fulfill() }
        try f.send(["do": "audio.inputMixer.set", "enabled": false]) { XCTAssertEqual($0.status, "applied") }
        f.access.answer?(true)
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting); XCTAssertTrue(f.call.effectiveInputUIDs.isEmpty)
    }
    func testRunningSourceEditWaitsForConfigurationACK() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let started = expectation(description: "started")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "applied"); started.fulfill() }
        f.access.answer?(true); f.session.startACK?(.success(()))
        await fulfillment(of: [started], timeout: 2)
        var result: AgentResultV2?
        let updated = expectation(description: "configuration ACK")
        try f.send(["do": "audio.inputSource.update", "source": "system", "gain": 0.3]) { result = $0; updated.fulfill() }
        XCTAssertNil(result); XCTAssertTrue(f.call.updating)
        f.session.updateACK?(.success(()))
        await fulfillment(of: [updated], timeout: 2)
        XCTAssertEqual(result?.status, "applied"); XCTAssertEqual(f.call.microphone.gain, 0.3)
    }
    func testStateReadDuringCaptureDoesNotReconfigureOrRequestPermission() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let started = expectation(description: "started")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "applied"); started.fulfill() }
        f.access.answer?(true); f.session.startACK?(.success(()))
        await fulfillment(of: [started], timeout: 2)
        let updates = f.session.updates, permissions = f.access.asked
        for _ in 0..<3 { _ = f.bridge.audioState(f.model) }
        await Task.yield()
        XCTAssertEqual(f.session.updates, updates); XCTAssertEqual(f.access.asked, permissions)
        XCTAssertTrue(f.call.running)
    }
    func testPermissionDenialRejectsAndDoesNotStartSession() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let denied = expectation(description: "denied")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.code, "audio_microphone_permission_denied"); denied.fulfill() }
        f.access.answer?(false)
        await fulfillment(of: [denied], timeout: 2)
        XCTAssertEqual(f.session.starts, 0); XCTAssertFalse(f.call.running)
    }
    func testUnacknowledgedStartTimesOutStopsAndLateACKCannotResume() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.bridge.audioAcknowledgementTimeout = .milliseconds(30)
        let timedOut = expectation(description: "unconfirmed start")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "indeterminate"); timedOut.fulfill() }
        f.access.answer?(true)
        await fulfillment(of: [timedOut], timeout: 2)
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
        f.session.startACK?(.success(()))
        XCTAssertFalse(f.call.running)
    }
    func testDeviceIncludedViaSystemRejectsBeforeSavingOrUpdating() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let started = expectation(description: "started")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "applied"); started.fulfill() }
        f.access.answer?(true); f.session.startACK?(.success(()))
        await fulfillment(of: [started], timeout: 2)
        let before = f.call.microphones, updates = f.session.updates
        try f.send(["do": "audio.inputSource.update", "source": "device", "sourceID": "fixture-mic", "muted": true]) {
            XCTAssertEqual($0.status, "rejected"); XCTAssertEqual($0.code, "audio_source_included_via_system")
        }
        XCTAssertEqual(f.call.microphones, before); XCTAssertEqual(f.session.updates, updates)
        XCTAssertFalse(f.call.microphone.muted)
    }
    func testDelayedDefaultNotificationRejectsBothObservedAndNewSystemAliases() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let started = expectation(description: "old default acknowledged")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "applied"); started.fulfill() }
        f.access.answer?(true); f.session.startACK?(.success(()))
        await fulfillment(of: [started], timeout: 2)
        f.hardware.additionalInputs = ["fixture-mic"]
        f.hardware.input = "fixture-new-mic"
        XCTAssertEqual(f.call.systemInputUID, "fixture-mic")
        XCTAssertEqual(f.sound.inputUID, "fixture-mic")
        let before = f.call.microphones, updates = f.session.updates
        for uid in ["fixture-mic", "fixture-new-mic"] {
            try f.send(["do": "audio.inputSource.update", "source": "device", "sourceID": uid, "muted": true]) {
                XCTAssertEqual($0.status, "rejected"); XCTAssertEqual($0.code, "audio_source_included_via_system")
            }
        }
        XCTAssertEqual(f.call.microphones, before); XCTAssertEqual(f.session.updates, updates)
        XCTAssertEqual(f.call.effectiveInputUIDs, ["fixture-mic"])
    }
    func testSameTurnStartStopStartCannotGiveOldStartNewACKOrStopNewGeneration() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.bridge.audioAcknowledgementTimeout = .milliseconds(30)
        let old = expectation(description: "old generation cancelled")
        var oldResult: AgentResultV2?
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { oldResult = $0; old.fulfill() }
        try f.send(["do": "audio.inputMixer.set", "enabled": false]) { XCTAssertEqual($0.status, "applied") }
        f.bridge.audioAcknowledgementTimeout = .seconds(1)
        let current = expectation(description: "current generation acknowledged")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "applied"); current.fulfill() }
        f.access.answer?(true)
        await fulfillment(of: [old], timeout: 2)
        XCTAssertEqual(oldResult?.code, "audio_input_start_cancelled")
        XCTAssertTrue(f.call.starting)
        f.session.startACK?(.success(()))
        await fulfillment(of: [current], timeout: 2)
        XCTAssertTrue(f.call.running)
    }
    func testTimeoutCompletionCanStartNewGenerationWithoutOldTimeoutStoppingIt() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.bridge.audioAcknowledgementTimeout = .milliseconds(30)
        let expired = expectation(description: "old start unconfirmed")
        let restarted = expectation(description: "new generation ready")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { result in
            XCTAssertEqual(result.status, "indeterminate")
            f.bridge.audioAcknowledgementTimeout = .seconds(1)
            do {
                try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "applied"); restarted.fulfill() }
                f.access.answer?(true); f.session.startACK?(.success(()))
            } catch { XCTFail("Synthetic restart failed: \(error)") }
            expired.fulfill()
        }
        f.access.answer?(true)
        await fulfillment(of: [expired, restarted], timeout: 2)
        XCTAssertTrue(f.call.running)
    }
    func testStopReceiptWaitsForActualSessionStopAcknowledgement() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let started = expectation(description: "started")
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.status, "applied"); started.fulfill() }
        f.access.answer?(true); f.session.startACK?(.success(()))
        await fulfillment(of: [started], timeout: 2)
        f.session.delayStop = true
        var result: AgentResultV2?
        let stopped = expectation(description: "actual stop acknowledged")
        try f.send(["do": "audio.inputMixer.set", "enabled": false]) { result = $0; stopped.fulfill() }
        XCTAssertNil(result); XCTAssertTrue(f.call.stopping)
        try f.send(["do": "audio.inputMixer.set", "enabled": true]) { XCTAssertEqual($0.code, "audio_input_busy") }
        try f.send(["do": "audio.inputSource.update", "source": "system", "gain": 0.4]) { XCTAssertEqual($0.code, "audio_input_busy") }
        f.session.stopACK?(.success(()))
        await fulfillment(of: [stopped], timeout: 2)
        XCTAssertEqual(result?.status, "applied")
    }
    func testExplicitMasterControlsWorkWithWindowClosedWithoutCapture() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let completed = expectation(description: "master acknowledged")
        try f.send(["do": "audio.master.volume", "direction": "output", "value": 0.2]) { XCTAssertEqual($0.status, "applied"); completed.fulfill() }
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(f.hardware.volume, 0.2); XCTAssertFalse(f.sound.windowOpen)
        XCTAssertEqual(f.access.asked, 0); XCTAssertEqual(f.session.starts, 0)
    }
}
