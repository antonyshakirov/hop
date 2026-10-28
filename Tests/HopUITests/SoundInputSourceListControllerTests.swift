import XCTest
import AppKit
import SwiftUI
import HopCore
@testable import Hop

@MainActor
final class SoundInputSourceListControllerTests: XCTestCase {
    private final class Session: SoundCallSession {
        var microphoneMuteChanged: ((Bool) -> Void)?
        var starts = 0, updates = 0
        func setMicrophoneMuted(_ value: Bool) -> Bool { false }
        func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { starts += 1 }
        func update(_ configuration: SoundCallConfiguration) { updates += 1 }
        func stop() {}
        func shutdown() {}
    }
    func testCollapsedSourceListAndRestorePopupFitContentAndLongListsReachTheScrollBoundary() {
        let previous = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = previous }
        let call = SoundCallMixController(enabled: true, session: Session(), access: { _ in XCTFail("Layout never captures") })
        let model = AppModel(preview: true, callController: call)
        model.sound.stageDemo("source-list")
        model.soundMixer.stageDemo()
        call.stageDemo(model.soundMixer.apps)
        func view(_ expanded: Bool) -> SoundCallMixView {
            .init(call: call, sound: model.sound, mixer: model.soundMixer, lang: .en, initiallyExpanded: expanded)
        }
        func size<V: View>(_ view: V) -> NSSize { NSHostingView(rootView: view).fittingSize }
        let compact = size(view(false).frame(width: 440)).height
        let expanded = size(view(true).frame(width: 440)).height
        XCTAssertLessThan(compact, 360)
        XCTAssertGreaterThan(expanded, compact + 60)
        call.stop()
        model.sound.stageDemo("source-list-many")
        call.stageDemo(model.soundMixer.apps)
        let manyDevices = size(view(false).frame(width: 440)).height
        XCTAssertGreaterThan(manyDevices, compact + 600)
        let frame = SoundWindowLayout.frame(current: .init(x: 0, y: 0, width: 520, height: 500),
            contentHeight: manyDevices + 250, chromeHeight: 28, visible: .init(x: 0, y: 0, width: 1000, height: 700), centered: false)
        XCTAssertLessThanOrEqual(frame.height, 668)
        let source = SoundInputListSource(id: .device("hidden"), name: "Hidden microphone", available: false)
        XCTAssertLessThan(size(view(false).hiddenSources([source])).height, 170)
        let many = (1...12).map { SoundInputListSource(id: .device("hidden-\($0)"), name: "Hidden microphone \($0)", available: false) }
        XCTAssertLessThanOrEqual(size(view(false).hiddenSources(many)).height, 320)
    }
    func testPresentationPersistsIndependentlyAndRestoresDisconnectedSourcesWithoutAudioChanges() throws {
        let suite = "Hop.InputList.Tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = Session()
        let call = SoundCallMixController(enabled: true, session: session, access: { _ in XCTFail("Presentation must not request microphone access") }, defaults: defaults)
        call.editMicrophone(uid: "fixture") { $0.gain = 0.37; $0.muted = true; $0.active = false }
        let audio = defaults.data(forKey: SoundCallMixController.preferencesKey)
        call.setSourcePinned(true, source: .device("fixture"), name: "Fixture Microphone")
        call.setSourcePinned(true, source: .application("fixture"), name: "Fixture App")
        XCTAssertTrue(call.setSourceHidden(true, source: .device("fixture"), name: "Fixture Microphone"))
        XCTAssertEqual(defaults.data(forKey: SoundCallMixController.preferencesKey), audio)
        let next = SoundCallMixController(enabled: true, session: session, defaults: defaults)
        let list = SoundInputSourceList(call: next, devices: [], applications: [])
        XCTAssertEqual(list.primary.map(\.id), [.application("fixture")])
        XCTAssertEqual(list.hidden.first?.name, "Fixture Microphone")
        XCTAssertEqual(list.hidden.first?.available, false)
        XCTAssertTrue(next.setSourceHidden(false, source: .device("fixture"), name: "Fixture Microphone"))
        XCTAssertEqual(SoundInputSourceList(call: next, devices: [], applications: []).other.map(\.id), [.device("fixture")])
        XCTAssertFalse(next.microphoneSettings(uid: "fixture").active)
        XCTAssertEqual(next.microphoneSettings(uid: "fixture").gain, 0.37)
        XCTAssertTrue(next.microphoneSettings(uid: "fixture").muted)
        XCTAssertEqual(defaults.data(forKey: SoundCallMixController.preferencesKey), audio)
        XCTAssertEqual(session.starts, 0); XCTAssertEqual(session.updates, 0)
    }
    func testConnectedPhysicalMicrophonesAreVisibleWithoutExpandingOtherSources() {
        let session = Session()
        let call = SoundCallMixController(enabled: true, session: session, access: { _ in XCTFail("Discovery never captures") })
        let devices: [SoundDevice] = [.init(uid: "builtin", name: "Built-in"),
            .init(uid: "headset", name: "Headset"), .init(uid: "virtual", name: "Virtual", isVirtual: true)]
        let app: SoundInputSourceID = .application("fixture.app")
        call.setSourcePinned(true, source: app, name: "App")
        func list() -> SoundInputSourceList {
            .init(call: call, devices: devices, applications: [("fixture.app", "App", true), ("unused.app", "Unused", true)])
        }
        XCTAssertEqual(list().primary.map(\.id), [app, .device("builtin"), .device("headset")])
        XCTAssertEqual(list().other.map(\.id), [.device("virtual"), .application("unused.app")])
        XCTAssertTrue(call.setSourceHidden(true, source: .device("headset"), name: "Headset"))
        XCTAssertEqual(list().primary.map(\.id), [app, .device("builtin")])
        XCTAssertEqual(list().hidden.map(\.id), [.device("headset")])
        call.editMicrophone(uid: "virtual") { $0.active = true }
        XCTAssertEqual(list().primary.map(\.id), [app, .device("virtual"), .device("builtin")])
        XCTAssertEqual(session.starts, 0); XCTAssertEqual(session.updates, 0)
    }
    func testSelectedSourceCannotBeHiddenAndSelectingAHiddenSourceRevealsItWhileStopped() {
        let session = Session()
        let call = SoundCallMixController(enabled: true, session: session, access: { _ in XCTFail("Stopped preset edits never capture") })
        let id = SoundInputSourceID.device("mic")
        XCTAssertTrue(call.setSourceHidden(true, source: id, name: "Mic"))
        call.editMicrophone(uid: "mic") { $0.active = true }
        XCTAssertFalse(call.sourceList.hidden.contains(id))
        XCTAssertFalse(call.setSourceHidden(true, source: id, name: "Mic"))
        XCTAssertEqual(SoundInputSourceList(call: call, devices: [.init(uid: "mic", name: "Mic")], applications: []).primary.map(\.id), [id])
        XCTAssertEqual(session.starts, 0); XCTAssertEqual(session.updates, 0)
    }
}
