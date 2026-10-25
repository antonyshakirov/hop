import XCTest
import HopCore
@testable import Hop

@MainActor
final class SoundCallMixControllerTests: XCTestCase {
    private final class Session: SoundCallSession {
        var microphoneMuteChanged: ((Bool) -> Void)?
        var mutes: [Bool] = []
        var muteAccepted = true
        func setMicrophoneMuted(_ value: Bool) -> Bool { mutes.append(value); return muteAccepted }
        var starts: [SoundCallConfiguration] = []
        var updates: [SoundCallConfiguration] = []
        var stops = 0
        var callback: ((Result<Void, SoundFailure>) -> Void)?
        func start(_ value: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { starts.append(value); callback = completed }
        func update(_ value: SoundCallConfiguration) { updates.append(value) }
        func stop() { stops += 1 }
        func shutdown() { stop() }
    }
    func testOfflinePinnedSourceIsOmittedAndRejoinsWithoutChangingSendSettings() {
        let session = Session()
        let mix = SoundCallMixController(enabled: true, session: session, access: { _ in XCTFail("No mic permission") })
        let app = SoundMixerChannel(id: "com.google.Chrome", name: "Chrome", input: false, settings: .init())
        mix.editApplication(app.id) { $0.active = true; $0.gain = 0.25 }
        mix.open(); mix.start(inputUID: nil, apps: [app]); session.callback?(.success(()))
        XCTAssertTrue(session.starts[0].apps.isEmpty)
        app.processes = [123]; mix.sourcesChanged([app])
        XCTAssertEqual(session.updates.last?.apps.first?.settings.gain, 0.25)
        app.processes = []; mix.sourcesChanged([app])
        XCTAssertTrue(session.updates.last!.apps.isEmpty)
        XCTAssertTrue(mix.running); XCTAssertTrue(mix.settings(app.id).active)
        mix.close()
    }
    func testDisabledPrototypeCannotAskForMicrophoneOrStart() {
        let session = Session(); var asked = false
        let mix = SoundCallMixController(enabled: false, session: session, access: { _ in asked = true })
        mix.open(); mix.start(inputUID: "mic", apps: [])
        XCTAssertFalse(asked); XCTAssertTrue(session.starts.isEmpty)
    }
    func testCloseDuringPermissionNeverStartsAndReopenRemainsStopped() {
        let session = Session(); var permission: ((Bool) -> Void)?
        let mix = SoundCallMixController(enabled: true, session: session, access: { permission = $0 })
        mix.editMicrophone { $0.active = true }
        mix.open(); mix.start(inputUID: "mic", apps: [])
        XCTAssertTrue(mix.starting)
        mix.close(); mix.open(); permission?(true)
        XCTAssertTrue(session.starts.isEmpty)
        XCTAssertFalse(mix.running); XCTAssertFalse(mix.starting)
    }
    func testCloseStopsRunningCaptureAndLateStartCannotResume() {
        let session = Session()
        let active = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        active.open(); active.start(inputUID: "mic", apps: [])
        session.callback?(.success(())); XCTAssertTrue(active.running)
        active.close(); active.open(); session.callback?(.success(()))
        XCTAssertFalse(active.running); XCTAssertFalse(active.starting)
        XCTAssertEqual(session.stops, 1)
    }
    func testOnlyExplicitAllowedAppsAndIndependentSettingsReachWorker() {
        let session = Session()
        let active = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        let chrome = SoundMixerChannel(id: "com.google.Chrome", name: "Chrome", input: false, settings: SoundChannelSettings())
        let zoom = SoundMixerChannel(id: "us.zoom.xos", name: "Zoom", input: false, settings: SoundChannelSettings())
        chrome.processes = [123]; zoom.processes = [456]
        active.open(); active.start(inputUID: "mic", apps: [chrome, zoom])
        XCTAssertTrue(session.starts[0].apps.isEmpty)
        active.stop()
        active.editApplication(chrome.id) { $0.active = true; $0.gain = 0.25 }
        active.editApplication(zoom.id) { $0.active = true }
        active.start(inputUID: "mic", apps: [chrome, zoom]); session.callback?(.success(()))
        XCTAssertEqual(session.starts[1].apps.map(\.id), [chrome.id])
        XCTAssertEqual(session.starts[1].apps[0].settings.gain, 0.25)
        XCTAssertEqual(chrome.settings.gain, 1)
        active.editMicrophone { $0.active = true; $0.muted = true }
        XCTAssertEqual(session.updates.last?.apps[0].settings.gain, 0.25)
        XCTAssertTrue(session.updates.last?.input?.settings.muted == true)
        active.close(); XCTAssertFalse(active.running)
    }
    func testDeviceChangeStopsRatherThanSelectingAnotherMicrophone() {
        let session = Session()
        let mix = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        mix.editMicrophone { $0.active = true }
        mix.open(); mix.start(inputUID: "micA", apps: []); session.callback?(.success(()))
        mix.inputChanged("micB")
        XCTAssertFalse(mix.running); XCTAssertEqual(mix.failure, .inputChanged)
        XCTAssertEqual(session.starts.count, 1)
    }
    func testEnableIncludesSelectedMicrophoneAndSourcesCanBeChangedLive() {
        let session = Session(); var requested = 0
        let mix = SoundCallMixController(enabled: true, session: session, access: { requested += 1; $0(true) })
        let app = SoundMixerChannel(id: "com.google.Chrome", name: "Chrome", input: false, settings: .init())
        app.processes = [123]
        mix.open(); mix.start(inputUID: "mic", apps: [app]); session.callback?(.success(()))
        XCTAssertEqual(requested, 1)
        XCTAssertEqual(session.starts[0].input?.uid, "mic")
        XCTAssertTrue(mix.microphone.active); XCTAssertTrue(session.starts[0].apps.isEmpty)
        mix.editApplication(app.id) { $0.active = true; $0.gain = 0.25 }
        XCTAssertEqual(session.updates.last?.apps.map(\.id), [app.id])
        XCTAssertEqual(session.updates.last?.apps[0].settings.gain, 0.25)
        mix.editMicrophone { $0.active = false }
        mix.editMicrophone { $0.active = true }
        XCTAssertEqual(requested, 2); XCTAssertEqual(session.updates.last?.input?.uid, "mic")
        mix.editApplication(app.id) { $0.active = false }
        XCTAssertTrue(session.updates.last?.apps.isEmpty == true)
        mix.editMicrophone { $0.active = false }
        XCTAssertNil(session.updates.last?.input)
        XCTAssertTrue(mix.running)
        mix.close(); mix.open(); mix.start(inputUID: "mic", apps: [app])
        XCTAssertEqual(session.starts.last?.input?.uid, "mic")
        XCTAssertEqual(requested, 3); XCTAssertTrue(session.starts.last?.apps.isEmpty == true)
    }
    func testNewAppCanBeSelectedAfterMixerHasStarted() {
        let session = Session()
        let mix = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        mix.open(); mix.start(inputUID: nil, apps: []); session.callback?(.success(()))
        let app = SoundMixerChannel(id: "com.google.Chrome", name: "Chrome", input: false, settings: .init())
        app.processes = [123]
        mix.sourcesChanged([app]); mix.editApplication(app.id) { $0.active = true }
        XCTAssertEqual(session.updates.last?.apps.map(\.id), [app.id])
        mix.sourcesChanged([])
        XCTAssertTrue(session.updates.last?.apps.isEmpty == true)
    }
    func testPendingLiveMicrophonePermissionCannotSurviveStopOrInputChange() {
        for close in [false, true] {
            let session = Session(); var permission: ((Bool) -> Void)?
            var initial = true
            let mix = SoundCallMixController(enabled: true, session: session, access: {
                if initial { initial = false; $0(true) } else { permission = $0 }
            })
            mix.open(); mix.start(inputUID: "micA", apps: []); session.callback?(.success(()))
            mix.editMicrophone { $0.active = false }
            let count = session.updates.count
            mix.editMicrophone { $0.active = true }
            XCTAssertTrue(mix.requestingMicrophone); XCTAssertFalse(mix.microphone.active)
            if close { mix.close() } else { mix.inputChanged("micB") }
            permission?(true)
            XCTAssertFalse(mix.running); XCTAssertFalse(mix.microphone.active)
            XCTAssertFalse(mix.requestingMicrophone)
            XCTAssertEqual(session.updates.count, count)
        }
    }
    func testDeniedLiveMicrophonePermissionKeepsMicrophoneOff() {
        let session = Session()
        var initial = true
        let mix = SoundCallMixController(enabled: true, session: session, access: {
            $0(initial); initial = false
        })
        mix.open(); mix.start(inputUID: "mic", apps: []); session.callback?(.success(()))
        mix.editMicrophone { $0.active = false }
        let count = session.updates.count
        mix.editMicrophone { $0.active = true }
        XCTAssertFalse(mix.microphone.active); XCTAssertEqual(mix.failure, .permission)
        XCTAssertTrue(mix.running); XCTAssertEqual(session.updates.count, count)
        XCTAssertNil(session.updates.last?.input)
    }

    func testAccessoryMuteUpdatesOnlyActiveMicrophoneAndUIRequiresAcceptance() {
        let session = Session()
        let mix = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        let app = SoundMixerChannel(id: "com.google.Chrome", name: "Chrome", input: false, settings: .init())
        mix.open(); mix.start(inputUID: "mic", apps: [app]); session.callback?(.success(()))
        mix.editMicrophone { $0.active = true }
        mix.editApplication(app.id) { $0.active = true; $0.gain = 0.25 }
        let updates = session.updates.count
        session.microphoneMuteChanged?(true)
        XCTAssertTrue(mix.microphone.muted); XCTAssertEqual(session.updates.count, updates)
        XCTAssertEqual(mix.settings(app.id).gain, 0.25); XCTAssertFalse(mix.settings(app.id).muted)
        session.muteAccepted = false
        mix.editMicrophone { $0.muted = false }; XCTAssertTrue(mix.microphone.muted)
        session.muteAccepted = true
        mix.editMicrophone { $0.muted = false }; XCTAssertFalse(mix.microphone.muted)
        mix.close(); session.microphoneMuteChanged?(true)
        XCTAssertFalse(mix.microphone.active); XCTAssertFalse(mix.microphone.muted)
    }

    func testConfirmedAccessoryStateDuringStartupIsNotLost() {
        let session = Session()
        let mix = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        mix.editMicrophone { $0.active = true }
        mix.open(); mix.start(inputUID: "mic", apps: [])
        XCTAssertTrue(mix.starting)
        session.microphoneMuteChanged?(true)
        session.callback?(.success(()))
        XCTAssertTrue(mix.running); XCTAssertTrue(mix.microphone.muted)
    }

    func testAutomaticMicrophoneWaitsForPermissionAndHonorsExistingMute() {
        let session = Session(); var permission: ((Bool) -> Void)?
        let mix = SoundCallMixController(enabled: true, session: session, access: { permission = $0 })
        mix.editMicrophone { $0.gain = 0.5; $0.muted = true }
        mix.open()
        XCTAssertTrue(session.starts.isEmpty); XCTAssertFalse(mix.microphone.active)
        mix.start(inputUID: "chosen-mic", apps: [])
        XCTAssertTrue(session.starts.isEmpty); XCTAssertTrue(mix.requestingMicrophone)
        permission?(true)
        XCTAssertEqual(session.starts.first?.input?.uid, "chosen-mic")
        XCTAssertEqual(session.starts.first?.input?.settings.gain, 0.5)
        XCTAssertTrue(session.starts.first?.input?.settings.muted == true)
    }

    func testAutomaticMicrophoneDeniedNeverStartsWorker() {
        let session = Session()
        let mix = SoundCallMixController(enabled: true, session: session, access: { $0(false) })
        mix.open(); mix.start(inputUID: "mic", apps: [])
        XCTAssertTrue(session.starts.isEmpty)
        XCTAssertFalse(mix.running); XCTAssertFalse(mix.starting)
        XCTAssertFalse(mix.requestingMicrophone); XCTAssertFalse(mix.microphone.active)
        XCTAssertEqual(mix.failure, .permission)
    }

    func testChangingInputWhileDefaultMicrophonePermissionIsPendingCancelsStart() {
        let session = Session(); var permission: ((Bool) -> Void)?
        let mix = SoundCallMixController(enabled: true, session: session, access: { permission = $0 })
        mix.open(); mix.start(inputUID: "micA", apps: [])
        mix.inputChanged("micB"); permission?(true)
        XCTAssertTrue(session.starts.isEmpty)
        XCTAssertFalse(mix.running); XCTAssertFalse(mix.microphone.active)
        XCTAssertEqual(mix.failure, .inputChanged)
    }

}
