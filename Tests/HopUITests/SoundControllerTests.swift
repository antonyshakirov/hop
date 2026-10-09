import XCTest
import HopCore
@testable import Hop

@MainActor
final class SoundControllerTests: XCTestCase {
    private final class Hardware: SoundHardware {
        var inputs = [SoundDevice(uid: "a", name: "mic A", volume: 0.8, muted: false, canChangeVolume: true, canMute: true),
                      SoundDevice(uid: "b", name: "mic B", volume: 0.6, muted: false, canChangeVolume: true, canMute: true)]
        var outputs = [SoundDevice(uid: "o", name: "output", volume: 0.5, muted: false, canChangeVolume: true, canMute: true)]
        var input = "a"
        var output = "o"
        var changed: (() -> Void)?
        var writes: [String] = []
        var watchers = 0
        var error: SoundFailure?
        func devices(_ direction: SoundDirection) -> [SoundDevice] { direction == .input ? inputs : outputs }
        func defaultUID(_ direction: SoundDirection) -> String? { direction == .input ? input : output }
        func select(_ uid: String, direction: SoundDirection) throws {
            if let error { throw error }
            guard devices(direction).contains(where: { $0.uid == uid }) else { throw SoundFailure.missingDevice }
            writes.append("select:\(uid)")
            if direction == .input { input = uid } else { output = uid }
        }
        func setVolume(_ volume: Double, uid: String, direction: SoundDirection) throws {
            if let error { throw error }
            writes.append("volume:\(uid)")
            if direction == .input { inputs[inputs.firstIndex { $0.uid == uid }!].volume = volume }
            else { outputs[0].volume = volume }
        }
        func setMute(_ muted: Bool, uid: String, direction: SoundDirection) throws {
            if let error { throw error }
            writes.append("mute:\(uid)")
            if direction == .input { inputs[inputs.firstIndex { $0.uid == uid }!].muted = muted }
            else { outputs[0].muted = muted }
        }
        func watch(_ changed: @escaping () -> Void) { self.changed = changed; watchers = 1 }
        func unwatch() { changed = nil; watchers = 0 }
    }

    private final class Meter: SoundMeter {
        var level = 0.4
        var duration = 0.0
        var hasRecording = false
        var plays = 0
        var clears = 0
        var playbackCompletion: (() -> Void)?
        var permitted = true
        var requests = 0
        var starts = 0
        var stops = 0
        var completion: ((Bool) -> Void)?
        var interrupted: (() -> Void)?
        func requestAccess(_ completion: @escaping (Bool) -> Void) { requests += 1; self.completion = completion }
        func start(_ uid: String, _ interrupted: @escaping () -> Void) throws {
            starts += 1; self.interrupted = interrupted; duration = 2; hasRecording = true
        }
        func play(_ completed: @escaping () -> Void) throws { plays += 1; playbackCompletion = completed }
        func clearRecording() { clears += 1; hasRecording = false; duration = 0 }
        func stop() { stops += 1 }
    }

    func testOpeningAndClosingDoNotCaptureOrChangeDeviceSettings() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.open()
        XCTAssertEqual(h.watchers, 1)
        XCTAssertEqual(c.inputUID, "a")
        XCTAssertTrue(h.writes.isEmpty)
        XCTAssertEqual(m.requests, 0)
        XCTAssertEqual(m.starts, 0)
        c.close()
        XCTAssertEqual(h.watchers, 0)
        XCTAssertFalse(c.windowOpen)
        XCTAssertTrue(h.writes.isEmpty)
    }

    func testLatePermissionGrantAfterCloseCannotStartCapture() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck()
        let pending = m.completion
        c.close(); c.open()
        pending?(true)
        XCTAssertEqual(m.starts, 0)
        XCTAssertFalse(c.checking)
        c.close()
    }

    func testPermissionDeniedShowsFailureAndDoesNotStart() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck(); m.completion?(false)
        XCTAssertEqual(c.failure, .permission)
        XCTAssertFalse(c.requestingAccess)
        XCTAssertEqual(m.starts, 0)
        c.close()
    }

    func testHotplugStopsMeterAndDoesNotRestartOrRestoreOldInput() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck(); m.completion?(true)
        XCTAssertTrue(c.checking)
        h.input = "b"; h.inputs.removeFirst(); h.changed?()
        XCTAssertEqual(c.inputUID, "b")
        XCTAssertFalse(c.checking)
        XCTAssertEqual(c.failure, .inputChanged)
        XCTAssertEqual(m.starts, 1)
        XCTAssertTrue(h.writes.isEmpty)
        c.close(); c.open()
        XCTAssertFalse(c.checking)
        c.close()
    }

    func testInputChangeDuringPermissionRequestCannotCaptureNewMicrophone() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck()
        h.input = "b"
        m.completion?(true)
        XCTAssertEqual(m.starts, 0)
        XCTAssertEqual(c.failure, .inputChanged)
        XCTAssertEqual(c.inputUID, "b")
        c.close()
    }

    func testOldEngineInterruptionCannotStopANewCheck() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck(); m.completion?(true)
        let old = m.interrupted
        c.stopCheck(); c.startCheck(); m.completion?(true)
        old?()
        XCTAssertTrue(c.checking)
        XCTAssertNil(c.failure)
        c.close()
    }

    func testGlobalMuteUsesCurrentSystemDefaultWithoutOpeningCapture() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        h.input = "b"
        c.toggleMute(.input)
        XCTAssertEqual(h.writes, ["mute:b"])
        XCTAssertEqual(h.inputs[0].muted, false)
        XCTAssertEqual(h.inputs[1].muted, true)
        XCTAssertEqual(m.requests, 0)
        XCTAssertEqual(h.watchers, 0)
        c.close()
    }

    func testUnsupportedMuteDoesNotSubstituteZeroGain() {
        let h = Hardware(), m = Meter()
        h.inputs[0].canMute = false
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.toggleMute(.input)
        XCTAssertEqual(c.failure, .unsupported)
        XCTAssertTrue(h.writes.isEmpty)
        XCTAssertEqual(h.inputs[0].volume, 0.8)
        c.close()
    }

    func testDisabledModuleCannotWriteOrAcceptPendingMicrophonePermission() {
        let h = Hardware(), m = Meter()
        var enabled = true
        let c = SoundController(hardware: h, meter: m, enabled: { enabled })
        c.open(); c.startCheck()
        enabled = false
        c.refresh(); m.completion?(true)
        c.toggleMute(.input); c.select("b", direction: .input)
        XCTAssertEqual(h.watchers, 0)
        XCTAssertEqual(m.starts, 0)
        XCTAssertTrue(h.writes.isEmpty)
        XCTAssertFalse(c.windowOpen)
        c.close()
    }

    func testStaleWindowControlsCannotModifyANewDefaultDevice() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open()
        h.input = "b"
        c.setVolume(0.1, direction: .input, expectedUID: "a")
        c.toggleMute(.input, expectedUID: "a")
        XCTAssertTrue(h.writes.isEmpty)
        XCTAssertEqual(c.inputUID, "b")
        XCTAssertEqual(c.failure, .inputChanged)
        c.close()
    }

    func testFailedRouteChangeDoesNotPretendNewDeviceIsSelected() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); h.error = .system(-50)
        c.select("b", direction: .input)
        XCTAssertEqual(c.inputUID, "a")
        XCTAssertEqual(c.failure, .system(-50))
        c.close()
    }

    func testRevokedPermissionStopsLevelTimerAndEngine() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck(); m.completion?(true)
        m.permitted = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertFalse(c.checking)
        XCTAssertEqual(c.level, 0)
        XCTAssertEqual(c.failure, .permission)
        c.close()
    }

    func testRecordingStopsAtLimitAndKeepsSampleForListening() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck(); m.completion?(true)
        m.duration = 10
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertFalse(c.checking)
        XCTAssertTrue(c.hasRecording)
        c.playRecording()
        XCTAssertEqual(m.plays, 1)
        c.close()
    }

    func testRealDeviceEnumerationIsReadOnlyAndUsesUniqueUIDs() {
        let hardware = CoreSoundHardware()
        for direction in SoundDirection.allCases {
            let devices = hardware.devices(direction)
            XCTAssertEqual(Set(devices.map(\.uid)).count, devices.count)
            XCTAssertTrue(devices.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty })
            XCTAssertTrue(devices.compactMap(\.volume).allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
    }
    func testVolumeDragUpdatesImmediatelyAndCoalescesHardwareWrites() async throws {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open()
        for i in 1...20 { c.setVolume(Double(i) / 20, direction: .output, expectedUID: "o") }
        XCTAssertEqual(c.device(.output)?.volume, 1)
        XCTAssertTrue(h.writes.isEmpty)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(h.writes, ["volume:o"])
        XCTAssertEqual(h.outputs[0].volume, 1)
        c.close()
    }

    func testClosingOrRouteSwitchCancelsQueuedVolumeWrite() async throws {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.setVolume(0.2, direction: .input, expectedUID: "a"); c.close()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(h.writes.isEmpty)
        c.open(); c.setVolume(0.3, direction: .input, expectedUID: "a"); h.input = "b"
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(h.writes.isEmpty)
        c.close()
    }

    func testSystemDefaultDoesNotWriteAndFollowsExternalDeviceChanges() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open()
        XCTAssertTrue(c.inputFollowsSystem)
        c.select("b", direction: .input)
        XCTAssertFalse(c.inputFollowsSystem)
        c.select("", direction: .input)
        XCTAssertTrue(c.inputFollowsSystem)
        XCTAssertEqual(h.writes, ["select:b"])
        h.input = "a"; h.changed?()
        XCTAssertEqual(c.inputUID, "a")
        XCTAssertTrue(c.inputFollowsSystem)
        c.close()
    }

    func testSampleCanBeListenedToAndIsDiscardedOnClose() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck(); m.completion?(true)
        XCTAssertFalse(c.hasRecording)
        c.stopCheck()
        XCTAssertTrue(c.hasRecording)
        XCTAssertEqual(c.duration, 2)
        c.playRecording()
        XCTAssertTrue(c.playing)
        XCTAssertEqual(m.plays, 1)
        m.playbackCompletion?()
        XCTAssertFalse(c.playing)
        c.playRecording(); let old = m.playbackCompletion
        c.stopPlayback(); c.playRecording()
        old?()
        XCTAssertTrue(c.playing)
        c.close()
        XCTAssertFalse(c.playing)
        XCTAssertFalse(c.hasRecording)
        XCTAssertFalse(m.hasRecording)
    }

    func testNewRecordingAndInputChangeDiscardOldSample() {
        let h = Hardware(), m = Meter()
        let c = SoundController(hardware: h, meter: m, enabled: { true })
        c.open(); c.startCheck(); m.completion?(true); c.stopCheck()
        c.startCheck()
        XCTAssertFalse(c.hasRecording)
        m.completion?(true); c.stopCheck(); c.playRecording()
        h.input = "b"; h.changed?()
        XCTAssertFalse(c.hasRecording)
        XCTAssertFalse(c.playing)
        c.close()
    }

    func testMuteStatusWatchesWhileEnabledAndStopsWhenDisabled() {
        let h = Hardware()
        let status = SoundMuteStatus(hardware: h)
        status.setEnabled(true)
        XCTAssertEqual(h.watchers, 1)
        h.inputs[0].muted = true; h.changed?()
        XCTAssertTrue(status.inputMuted)
        XCTAssertFalse(status.outputMuted)
        h.input = "b"; h.changed?()
        XCTAssertFalse(status.inputMuted)
        status.setEnabled(false)
        XCTAssertEqual(h.watchers, 0)
        h.inputs[1].muted = true; h.changed?()
        XCTAssertFalse(status.inputMuted)
    }

}
