import XCTest
import HopCore
@testable import Hop

@MainActor
final class SoundQuickInputLifecycleTests: XCTestCase {
    private final class Hardware: SoundHardware {
        var uid: String? = "fixture-mic"
        var changed: (() -> Void)?
        var watchers = 0
        func devices(_ direction: SoundDirection) -> [SoundDevice] {
            guard direction == .input, let uid else { return [] }
            return [SoundDevice(uid: uid, name: "Fixture", volume: 1, muted: false, canChangeVolume: true, canMute: true)]
        }
        func defaultUID(_ direction: SoundDirection) -> String? { direction == .input ? uid : nil }
        func select(_ uid: String, direction: SoundDirection) throws { XCTFail("No hardware writes") }
        func setVolume(_ volume: Double, uid: String, direction: SoundDirection) throws { XCTFail("No hardware writes") }
        func setMute(_ muted: Bool, uid: String, direction: SoundDirection) throws { XCTFail("No hardware writes") }
        func watch(_ changed: @escaping () -> Void) { self.changed = changed; watchers = 1 }
        func unwatch() { changed = nil; watchers = 0 }
    }
    private final class Meter: SoundMeter {
        let level = 0.0
        let permitted = false
        func requestAccess(_ completion: @escaping (Bool) -> Void) { XCTFail("No microphone sample permission") }
        func start(_ uid: String, _ interrupted: @escaping () -> Void) throws { XCTFail("No microphone samples") }
        func stop() {}
    }
    private final class Session: SoundCallSession {
        var microphoneMuteChanged: ((Bool) -> Void)?
        var starts: [SoundCallConfiguration] = []
        var updates: [SoundCallConfiguration] = []
        var stops = 0
        var completion: ((Result<Void, SoundFailure>) -> Void)?
        func setMicrophoneMuted(_ value: Bool) -> Bool { true }
        func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
            starts.append(configuration); completion = completed
        }
        func update(_ configuration: SoundCallConfiguration) { updates.append(configuration) }
        func stop() { stops += 1 }
        func shutdown() { stop() }
    }
    private final class State {
        var enabled = true
        var permission: ((Bool) -> Void)?
        var processes: [UInt32] = [100]
        var appPresent = true
        var additionalApps = 0
        var opens = 0
    }
    @MainActor
    private final class Fixture {
        let state = State()
        let hardware = Hardware()
        let session = Session()
        let sound: SoundController
        let mixer: SoundMixerController
        let call: SoundCallMixController
        let model: AppModel
        let defaults: UserDefaults
        let suite = "HopTests.QuickInput." + UUID().uuidString

        init(legacyOpen: Bool = true) {
            let state = state
            defaults = UserDefaults(suiteName: suite)!
            sound = SoundController(hardware: hardware, meter: Meter(), enabled: { state.enabled })
            mixer = SoundMixerController(enabled: { state.enabled }, defaults: defaults, makeSession: { _ in
                XCTFail("Quick Input must not start Output")
                return OutputSession()
            }, discover: {
                guard state.appPresent else { return [] }
                return (0...state.additionalApps).map { index in
                    SoundMixerAppSnapshot(id: index == 0 ? "fixture.app" : "fixture.app.\(index)", name: "Fixture \(index)",
                        processes: state.processes, appRunning: true, sourceRunning: !state.processes.isEmpty)
                }
            }, outputs: { [] })
            call = SoundCallMixController(enabled: true, session: session, access: { state.permission = $0 })
            model = AppModel(preview: true, soundController: sound, mixerController: mixer,
                callController: call, soundEnabled: { state.enabled })
            let sound = sound, mixer = mixer, call = call
            model.openSoundWindow = {
                state.opens += 1
                if legacyOpen { sound.open(); mixer.open(); call.open() }
            }
        }
        func cleanup() {
            call.shutdown(); sound.close(); mixer.close(); defaults.removePersistentDomain(forName: suite)
        }
        func ready() {
            model.startQuickInput(); state.permission?(true); session.completion?(.success(()))
        }
    }
    private final class OutputSession: SoundMixingSession {
        func outputs(_ channels: [SoundMixerChannel]) {}
        func configure(_ channel: SoundMixerChannel) {}
        func stop() {}
    }

    func testInitializationAndOpeningOnlyDoNotStartInput() {
        let f = Fixture(); defer { f.cleanup() }
        XCTAssertNil(f.state.permission)
        XCTAssertTrue(f.session.starts.isEmpty)
        XCTAssertEqual(f.hardware.watchers, 0)
        f.sound.open(); f.mixer.open(); f.call.open()
        XCTAssertNil(f.state.permission)
        XCTAssertTrue(f.session.starts.isEmpty)
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
    }

    func testQuickInputStartsWithoutOpeningWindowOrRequestingPage() {
        let f = Fixture(); defer { f.cleanup() }
        f.ready()
        XCTAssertEqual(f.state.opens, 0)
        XCTAssertNil(f.model.soundPageRequest)
        XCTAssertFalse(f.sound.windowOpen)
        XCTAssertTrue(f.call.running)
        XCTAssertEqual(f.session.starts.first?.input?.uid, "fixture-mic")
        XCTAssertFalse(f.mixer.running); XCTAssertFalse(f.mixer.requested)
    }

    func testExplicitQuickStartDoesNotRequireControllerOpen() {
        let session = Session(); var permission: ((Bool) -> Void)?
        let call = SoundCallMixController(enabled: true, session: session, access: { permission = $0 })
        defer { call.shutdown() }
        call.startQuick(inputUID: "fixture-mic", apps: [])
        XCTAssertTrue(call.starting)
        permission?(true); session.completion?(.success(()))
        XCTAssertTrue(call.running)
        XCTAssertEqual(session.starts.first?.input?.uid, "fixture-mic")
    }

    func testInputLossBeforeAnyWindowExistsStopsCaptureAndReleasesObservation() {
        let f = Fixture(); defer { f.cleanup() }
        f.ready()
        XCTAssertTrue(f.call.running)
        f.hardware.uid = nil; f.hardware.changed?()
        XCTAssertFalse(f.call.running)
        XCTAssertEqual(f.call.failure, .inputChanged)
        XCTAssertEqual(f.hardware.watchers, 0)
        XCTAssertEqual(f.session.starts.count, 1)
    }

    func testLiveApplicationProcessesReachInputWithoutSoundView() {
        let f = Fixture(); defer { f.cleanup() }
        f.ready()
        f.call.editApplication("fixture.app") { $0.active = true }
        XCTAssertEqual(f.session.updates.last?.apps.first?.processes, [100])
        f.state.processes = [200]
        f.mixer.open() // Publish a fresh result from fake discovery, without creating a view.
        XCTAssertEqual(f.session.updates.last?.apps.first?.processes, [200])
        f.state.processes = []
        f.mixer.open()
        XCTAssertTrue(f.session.updates.last?.apps.isEmpty == true)
    }

    func testQuickStopCancelsPendingPermissionAndReleasesObservation() {
        let f = Fixture(); defer { f.cleanup() }
        f.model.startQuickInput()
        XCTAssertTrue(f.call.starting)
        f.call.stop(); f.state.permission?(true)
        XCTAssertTrue(f.session.starts.isEmpty)
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
        XCTAssertEqual(f.hardware.watchers, 0)
    }

    func testInputLossDuringPermissionCancelsStartAndNeverChoosesReplacement() {
        let f = Fixture(); defer { f.cleanup() }
        f.model.startQuickInput()
        f.hardware.uid = "different-mic"; f.hardware.changed?()
        f.state.permission?(true)
        XCTAssertTrue(f.session.starts.isEmpty)
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
        XCTAssertEqual(f.call.failure, .inputChanged)
        XCTAssertEqual(f.hardware.watchers, 0)
    }

    func testNormalWindowStartRejectsInputChangedBeforeObservationLeaseStarts() {
        let f = Fixture(); defer { f.cleanup() }
        f.sound.open(); f.mixer.open(); f.call.open()
        XCTAssertEqual(f.sound.inputUID, "fixture-mic")
        f.hardware.uid = "different-mic"

        f.call.start(inputUID: f.sound.inputUID, apps: f.mixer.apps)
        f.state.permission?(true)

        XCTAssertEqual(f.sound.inputUID, "different-mic", "Starting observation must refresh the current hardware UID")
        XCTAssertTrue(f.session.starts.isEmpty, "The stale microphone must never reach the worker")
        XCTAssertFalse(f.call.starting)
        XCTAssertFalse(f.call.running)
        XCTAssertEqual(f.call.failure, .inputChanged)
    }

    func testNormalWindowStartOmitsApplicationRemovedByPreflightRefresh() {
        let f = Fixture(); defer { f.cleanup() }
        f.hardware.uid = nil
        f.sound.open(); f.mixer.open(); f.call.open()
        f.call.editApplication("fixture.app") { $0.active = true }
        XCTAssertEqual(f.mixer.apps.first?.processes, [100])
        f.state.appPresent = false

        f.call.start(inputUID: nil, apps: f.mixer.apps)

        XCTAssertTrue(f.mixer.apps.isEmpty, "Preflight must observe the disappeared unpinned application")
        XCTAssertEqual(f.session.starts.count, 1)
        XCTAssertTrue(f.session.starts.first?.apps.isEmpty == true, "The worker must receive the fresh source snapshot")
    }

    func testFreshSourceLimitRejectionReleasesPreflightObservation() {
        let f = Fixture(); defer { f.cleanup() }
        f.hardware.uid = nil
        for index in 0...4 {
            f.call.editApplication(index == 0 ? "fixture.app" : "fixture.app.\(index)") { $0.active = true }
        }
        f.state.additionalApps = 4
        f.call.open()

        f.call.start(inputUID: nil, apps: [])

        XCTAssertEqual(f.mixer.apps.count, 5, "Preflight must validate the refreshed source set")
        XCTAssertTrue(f.session.starts.isEmpty)
        XCTAssertFalse(f.call.starting)
        XCTAssertFalse(f.call.running)
        XCTAssertNotNil(f.call.failure)
        XCTAssertEqual(f.hardware.watchers, 0, "Rejected post-preflight validation must release Input observation")
    }

    func testModuleOffCancelsPendingPermissionWithoutRetry() {
        let f = Fixture(); defer { f.cleanup() }
        f.model.startQuickInput()
        f.state.enabled = false
        NotificationCenter.default.post(name: ModuleActivation.didChange, object: nil)
        f.state.permission?(true)
        XCTAssertTrue(f.session.starts.isEmpty)
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
        XCTAssertEqual(f.hardware.watchers, 0)
        f.state.enabled = true
        NotificationCenter.default.post(name: ModuleActivation.didChange, object: nil)
        XCTAssertTrue(f.session.starts.isEmpty)
    }

    func testLaterOpeningAndClosingSoundStillStopsQuickCapture() {
        let f = Fixture(); defer { f.cleanup() }
        f.ready(); f.call.open(); f.call.close()
        f.session.completion?(.success(()))
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
        XCTAssertEqual(f.hardware.watchers, 0)
        f.call.open()
        XCTAssertFalse(f.call.running)
        XCTAssertEqual(f.session.starts.count, 1)
    }

    func testShutdownCancelsLatePermissionWithoutStartingSession() {
        let f = Fixture(); defer { f.cleanup() }
        f.model.startQuickInput(); f.call.shutdown(); f.state.permission?(true)
        XCTAssertTrue(f.session.starts.isEmpty)
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
        XCTAssertEqual(f.hardware.watchers, 0)
    }

    func testFailedStartupReleasesObservationAndNeverRetries() {
        let f = Fixture(); defer { f.cleanup() }
        f.model.startQuickInput(); f.state.permission?(true)
        f.session.completion?(.failure(.system(-1)))
        XCTAssertFalse(f.call.running); XCTAssertFalse(f.call.starting)
        XCTAssertEqual(f.hardware.watchers, 0)
        f.hardware.changed?()
        XCTAssertEqual(f.session.starts.count, 1)
    }
}
