import XCTest
import HopCore
@testable import Hop

@MainActor
final class SoundInputPresetControllerTests: XCTestCase {
    private final class Session: SoundCallSession {
        var microphoneMuteChanged: ((Bool) -> Void)?
        var starts: [SoundCallConfiguration] = []
        var updates: [SoundCallConfiguration] = []
        var startAck: ((Result<Void, SoundFailure>) -> Void)?
        var updateAcks: [(Result<Void, SoundFailure>) -> Void] = []
        var stopResult: Result<Void, SoundFailure> = .success(())
        func setMicrophoneMuted(_ value: Bool) -> Bool { false }
        func start(_ value: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
            starts.append(value); startAck = completed
        }
        func update(_ value: SoundCallConfiguration) { updates.append(value) }
        func update(_ value: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
            updates.append(value); updateAcks.append(completed)
        }
        func stop() {}
        func stop(completed: @escaping (Result<Void, SoundFailure>) -> Void) { completed(stopResult) }
        func shutdown() {}
    }
    private let devices = [SoundDevice(uid: "mac", name: "Mac"), SoundDevice(uid: "pods", name: "AirPods")]

    func testDeviceRemovalFailureIsVisibleAndSuccessfulCleanupClearsItWithoutChangingPreset() {
        let session = Session()
        let call = SoundCallMixController(enabled: true, session: session, access: { _ in XCTFail("Cleanup never requests audio") })
        call.editMicrophone { $0.gain = 0.37; $0.muted = true }
        session.stopResult = .failure(.inputRemoval)
        call.stop()
        XCTAssertEqual(call.failure, .inputRemoval)
        XCTAssertFalse(call.stopping)
        XCTAssertFalse(call.running)
        session.stopResult = .success(())
        call.stop()
        XCTAssertNil(call.failure)
        XCTAssertEqual(call.microphone.gain, 0.37)
        XCTAssertTrue(call.microphone.muted)
        XCTAssertTrue(session.starts.isEmpty)
    }

    func testDefaultAndNamedMicrophonesDeduplicateThenFollowDefaultWithIndependentLevels() {
        let session = Session()
        let call = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        call.inputsChanged(defaultUID: "pods", devices: devices)
        call.editMicrophone { $0.gain = 0.5 }
        call.editMicrophone(uid: "mac") { $0.active = true; $0.gain = 0.25 }
        call.editMicrophone(uid: "pods") { $0.active = true; $0.gain = 0.75 }
        call.open(); call.start(inputUID: "pods", apps: [])
        XCTAssertEqual(session.starts[0].inputs.map(\.uid), ["pods", "mac"])
        XCTAssertEqual(session.starts[0].inputs.map(\.settings.gain), [0.5, 0.25])
        XCTAssertTrue(call.effectiveInputUIDs.isEmpty)
        session.startAck?(.success(()))
        XCTAssertEqual(call.effectiveInputUIDs, ["pods", "mac"])
        call.inputsChanged(defaultUID: "mac", devices: devices)
        XCTAssertEqual(session.updates.last?.inputs.map(\.uid), ["mac", "pods"])
        XCTAssertEqual(session.updates.last?.inputs.map(\.settings.gain), [0.5, 0.75])
        XCTAssertEqual(call.effectiveInputUIDs, ["pods", "mac"])
        session.updateAcks.last?(.success(()))
        XCTAssertEqual(call.effectiveInputUIDs, ["mac", "pods"])
        call.stop(); XCTAssertTrue(call.effectiveInputUIDs.isEmpty)
    }

    func testSavedOffAndLevelsSurviveStopFailureAndNewControllerWithoutCapturingOnLoad() throws {
        let name = "Hop.InputPreset.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = Session()
        let call = SoundCallMixController(enabled: true, session: session, access: { _ in XCTFail("Default is off") }, defaults: defaults)
        call.editMicrophone { $0.active = false; $0.gain = 0.3; $0.muted = true }
        call.editMicrophone(uid: "pods") { $0.active = true; $0.gain = 0.4 }
        call.editApplication("com.spotify.client") { $0.active = true; $0.gain = 0.2 }
        call.open(); call.start(inputUID: "mac", apps: [])
        session.startAck?(.failure(.system(-1)))
        let nextSession = Session()
        let next = SoundCallMixController(enabled: true, session: nextSession, defaults: defaults)
        XCTAssertFalse(next.microphone.active); XCTAssertTrue(next.microphone.muted)
        XCTAssertEqual(next.microphone.gain, 0.3)
        XCTAssertEqual(next.microphoneSettings(uid: "pods").gain, 0.4)
        XCTAssertTrue(next.microphoneSettings(uid: "pods").active)
        XCTAssertEqual(next.settings("com.spotify.client").gain, 0.2)
        XCTAssertTrue(nextSession.starts.isEmpty); XCTAssertFalse(next.running)
    }

    func testSupersededUpdateAndLateAcknowledgementCannotReportCurrentOrRestartStoppedCapture() {
        let session = Session()
        let call = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        call.inputsChanged(defaultUID: "mac", devices: devices)
        call.open(); call.start(inputUID: "mac", apps: []); session.startAck?(.success(()))
        call.editMicrophone { $0.active = false }
        call.editMicrophone(uid: "pods") { $0.active = true }
        let latest = call.configurationRevision
        session.updateAcks[0](.success(()))
        XCTAssertTrue(call.updating); XCTAssertNotEqual(call.appliedConfigurationRevision, latest)
        session.updateAcks[1](.success(()))
        XCTAssertFalse(call.updating); XCTAssertEqual(call.effectiveInputUIDs, ["pods"])
        call.stop(); session.updateAcks[1](.success(())); session.startAck?(.success(()))
        XCTAssertFalse(call.running); XCTAssertTrue(call.effectiveInputUIDs.isEmpty)
    }
}
