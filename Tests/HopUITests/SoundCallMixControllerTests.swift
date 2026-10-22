import XCTest
import HopCore
@testable import Hop

@MainActor
final class SoundCallMixControllerTests: XCTestCase {
    private final class Session: SoundCallSession {
        var starts: [SoundCallConfiguration] = []
        var updates: [SoundCallConfiguration] = []
        var stops = 0
        var callback: ((Result<Void, SoundFailure>) -> Void)?
        func start(_ value: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { starts.append(value); callback = completed }
        func update(_ value: SoundCallConfiguration) { updates.append(value) }
        func stop() { stops += 1 }
        func shutdown() { stop() }
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
        active.editMicrophone { $0.muted = true }
        XCTAssertEqual(session.updates.last?.apps[0].settings.gain, 0.25)
        XCTAssertTrue(session.updates.last?.input?.settings.muted == true)
        active.close(); XCTAssertFalse(active.running)
    }
    func testDeviceChangeStopsRatherThanSelectingAnotherMicrophone() {
        let session = Session()
        let mix = SoundCallMixController(enabled: true, session: session, access: { $0(true) })
        mix.open(); mix.start(inputUID: "micA", apps: []); session.callback?(.success(()))
        mix.inputChanged("micB")
        XCTAssertFalse(mix.running); XCTAssertEqual(mix.failure, .inputChanged)
        XCTAssertEqual(session.starts.count, 1)
    }
}
