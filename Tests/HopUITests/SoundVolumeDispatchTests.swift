import HopCore
import XCTest
@testable import Hop

@MainActor
final class SoundVolumeDispatchTests: XCTestCase {
    private struct Write: Equatable {
        var value: Double
        var uid: String
        var direction: SoundDirection
    }
    private final class Hardware: SoundHardware {
        var output = "a"
        var input = "mic"
        var outputDevices = [SoundDevice(uid: "a", name: "A", volume: 0.5, canChangeVolume: true),
                             SoundDevice(uid: "b", name: "B", volume: 0.6, canChangeVolume: true)]
        var inputDevices = [SoundDevice(uid: "mic", name: "Microphone", volume: 0.5, canChangeVolume: true)]
        var changed: (() -> Void)?
        var outputVolumeChanged: (() -> Void)?
        var starts: [Write] = []
        var applied: [Write] = []
        var synchronousWrites: [Write] = []
        var pending: [(Write, CheckedContinuation<Bool, Error>)] = []
        var active = 0
        var maximumActive = 0
        var deviceQueries = 0
        func devices(_ direction: SoundDirection) -> [SoundDevice] {
            deviceQueries += 1
            return direction == .output ? outputDevices : inputDevices
        }
        func defaultUID(_ direction: SoundDirection) -> String? { direction == .output ? output : input }
        func select(_ uid: String, direction: SoundDirection) throws {}
        func setVolume(_ volume: Double, uid: String, direction: SoundDirection) throws {
            synchronousWrites.append(Write(value: volume, uid: uid, direction: direction))
        }
        func setVolumeAsync(_ volume: Double, uid: String, direction: SoundDirection) async throws {
            let write = Write(value: volume, uid: uid, direction: direction)
            starts.append(write); active += 1; maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            let publish = try await withCheckedThrowingContinuation { pending.append((write, $0)) }
            try Task.checkCancellation()
            guard defaultUID(direction) == uid else { throw SoundFailure.missingDevice }
            applied.append(write)
            if publish {
                if direction == .output { outputDevices[outputDevices.firstIndex { $0.uid == uid }!].volume = volume }
                else { inputDevices[0].volume = volume }
                volumeEvent()
            }
        }
        func finishNext(publish: Bool = true) {
            guard !pending.isEmpty else { return }
            pending.removeFirst().1.resume(returning: publish)
        }
        func finishAll() { while !pending.isEmpty { finishNext(publish: false) } }
        func setMute(_ muted: Bool, uid: String, direction: SoundDirection) throws {}
        func watch(_ changed: @escaping () -> Void) { self.changed = changed }
        func watch(_ changed: @escaping () -> Void, outputVolumeChanged: @escaping () -> Void) {
            self.changed = changed; self.outputVolumeChanged = outputVolumeChanged
        }
        func volumeEvent() { if let outputVolumeChanged { outputVolumeChanged() } else { changed?() } }
        func unwatch() { changed = nil; outputVolumeChanged = nil }
    }
    private final class Meter: SoundMeter {
        var level: Double { 0 }
        var permitted: Bool { false }
        func requestAccess(_ completion: @escaping (Bool) -> Void) { XCTFail("Volume cannot request microphone access") }
        func start(_ uid: String, _ interrupted: @escaping () -> Void) throws { XCTFail("Volume cannot start microphone capture") }
        func stop() {}
    }
    private func settle() async { for _ in 0..<40 { await Task.yield() } }
    private func controller(_ hardware: Hardware) -> SoundController {
        let controller = SoundController(hardware: hardware, meter: Meter(), enabled: { true })
        controller.open()
        return controller
    }

    func testFirstWriteDispatchesWithoutDebounceAndUsesAsyncHardwareInterface() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a")
        await settle()
        XCTAssertEqual(hardware.starts, [Write(value: 0.2, uid: "a", direction: .output)])
        XCTAssertTrue(hardware.synchronousWrites.isEmpty)
        sound.close(); hardware.finishAll(); await settle()
    }

    func testInflightWritesKeepOnlyLatestValueAndDoNotRewindOptimisticVolume() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a"); await settle()
        for value in 1...20 { sound.setVolume(Double(value) / 20, direction: .output, expectedUID: "a") }
        hardware.volumeEvent(); await settle()
        XCTAssertEqual(sound.device(.output)?.volume, 1)
        XCTAssertEqual(hardware.starts.count, 1)
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.starts.map(\.value), [0.2, 1])
        XCTAssertEqual(sound.device(.output)?.volume, 1)
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.applied.map(\.value), [0.2, 1]); XCTAssertEqual(hardware.maximumActive, 1)
        sound.close(); hardware.finishAll(); await settle()
    }

    func testStaleReadbackAfterWriteReturnsDoesNotRewindTargetAndLaterExternalValueWins() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a"); await settle()
        hardware.finishNext(publish: false); await settle()
        XCTAssertEqual(sound.device(.output)?.volume, 0.2)
        hardware.volumeEvent(); await settle()
        XCTAssertEqual(sound.device(.output)?.volume, 0.2)
        hardware.outputDevices[0].volume = 0.2; hardware.volumeEvent(); await settle()
        hardware.outputDevices[0].volume = 0.7; hardware.volumeEvent(); await settle()
        XCTAssertEqual(sound.device(.output)?.volume, 0.7)
        sound.close(); hardware.finishAll(); await settle()
    }

    func testLateAcknowledgementOfSupersededWriteCannotRewindLatestTarget() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a"); await settle()
        sound.setVolume(0.9, direction: .output, expectedUID: "a")
        hardware.finishNext(publish: false); await settle()
        hardware.finishNext(publish: false); await settle()
        XCTAssertEqual(hardware.starts.map(\.value), [0.2, 0.9])
        XCTAssertEqual(sound.device(.output)?.volume, 0.9)
        hardware.outputDevices[0].volume = 0.2; hardware.volumeEvent(); await settle()
        XCTAssertEqual(sound.device(.output)?.volume, 0.9)
        hardware.outputDevices[0].volume = 0.9; hardware.volumeEvent(); await settle()
        hardware.outputDevices[0].volume = 0.7; hardware.volumeEvent(); await settle()
        XCTAssertEqual(sound.device(.output)?.volume, 0.7)
        sound.close(); hardware.finishAll(); await settle()
    }

    func testUnacknowledgedTargetExpiresInsteadOfHidingHardwareStateForever() async throws {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a"); await settle()
        hardware.finishNext(publish: false); await settle()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(sound.device(.output)?.volume, 0.5)
        sound.close(); hardware.finishAll(); await settle()
    }

    func testClosingDropsQueuedValueAndCannotWriteItAfterInflightCompletes() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a"); await settle()
        sound.setVolume(0.9, direction: .output, expectedUID: "a")
        sound.close(); hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.starts.count, 1)
        XCTAssertTrue(hardware.applied.isEmpty)
        hardware.finishAll(); await settle()
    }

    func testCloseAndReopenNeverOverlapOldAndNewHardwareWrites() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a"); await settle()
        sound.close(); sound.open(); sound.setVolume(0.9, direction: .output, expectedUID: "a"); await settle()
        XCTAssertEqual(hardware.starts.count, 1)
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.starts.map(\.value), [0.2, 0.9])
        XCTAssertEqual(hardware.maximumActive, 1)
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.applied.map(\.value), [0.9])
        sound.close(); hardware.finishAll(); await settle()
    }

    func testRouteSwitchCancelsOldQueuedValueAndSerializesNewDestination() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output, expectedUID: "a"); await settle()
        sound.setVolume(0.4, direction: .output, expectedUID: "a")
        hardware.output = "b"; hardware.changed?()
        sound.setVolume(0.8, direction: .output, expectedUID: "b"); await settle()
        XCTAssertEqual(hardware.starts.count, 1)
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.starts.map(\.uid), ["a", "b"])
        XCTAssertEqual(hardware.starts.last?.value, 0.8)
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.applied, [Write(value: 0.8, uid: "b", direction: .output)])
        sound.close(); hardware.finishAll(); await settle()
    }

    func testClosingInputControlsCancelsQueuedInputWithoutCancelingOutput() async {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.3, direction: .output, expectedUID: "a")
        sound.setVolume(0.2, direction: .input, expectedUID: "mic"); await settle()
        sound.setVolume(0.8, direction: .input, expectedUID: "mic")
        sound.closeControls(.input); hardware.finishAll(); await settle()
        XCTAssertTrue(sound.windowOpen)
        XCTAssertEqual(hardware.applied, [Write(value: 0.3, uid: "a", direction: .output)])
        XCTAssertFalse(hardware.starts.contains { $0.direction == .input && $0.value == 0.8 })
        sound.close(); hardware.finishAll(); await settle()
    }

    func testOutputVolumeNotificationBurstCoalescesCatalogQueries() async {
        let hardware = Hardware(), sound = controller(hardware)
        let before = hardware.deviceQueries
        for _ in 0..<20 { hardware.volumeEvent() }
        await settle()
        XCTAssertLessThanOrEqual(hardware.deviceQueries - before, 2)
        sound.close(); hardware.finishAll(); await settle()
    }

    func testAgentWaitsForInflightUIWriteAndNewUserValueWaitsForAgent() async throws {
        let hardware = Hardware(), sound = controller(hardware)
        sound.setVolume(0.2, direction: .output); await settle()
        let agent = Task { try await sound.setAgentVolume(0.6, direction: .output, expectedUID: "a") }
        await settle()
        sound.setVolume(0.9, direction: .output); await settle()
        XCTAssertEqual(hardware.starts.map(\.value), [0.2])
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.starts.map(\.value), [0.2, 0.6])
        hardware.finishNext(); try await agent.value; await settle()
        XCTAssertEqual(hardware.starts.map(\.value), [0.2, 0.6, 0.9])
        hardware.finishNext(); await settle()
        XCTAssertEqual(hardware.applied.map(\.value), [0.2, 0.6, 0.9])
        XCTAssertEqual(hardware.maximumActive, 1)
        sound.close()
    }

    func testCancelledQueuedAgentCannotWriteAfterPrecedingAgentFinishes() async throws {
        let hardware = Hardware()
        let sound = SoundController(hardware: hardware, meter: Meter(), enabled: { true })
        let first = Task { try await sound.setAgentVolume(0.2, direction: .output, expectedUID: "a") }
        await settle()
        let cancelled = Task { try await sound.setAgentVolume(0.8, direction: .output, expectedUID: "a") }
        await settle(); cancelled.cancel()
        hardware.finishNext(); try await first.value
        do { try await cancelled.value; XCTFail("Cancelled queued command must fail") } catch {}
        await settle()
        XCTAssertEqual(hardware.starts.map(\.value), [0.2]); XCTAssertEqual(hardware.maximumActive, 1)
        XCTAssertFalse(sound.windowOpen); XCTAssertFalse(sound.checking)
    }

    func testQueuedAgentRevalidatesDeviceAfterRouteChanges() async throws {
        let hardware = Hardware()
        let sound = SoundController(hardware: hardware, meter: Meter(), enabled: { true })
        let first = Task { try await sound.setAgentVolume(0.2, direction: .output, expectedUID: "a") }
        await settle()
        let stale = Task { try await sound.setAgentVolume(0.8, direction: .output, expectedUID: "a") }
        await settle(); hardware.output = "b"; hardware.finishNext()
        do { try await first.value; XCTFail("Changed route must fail") } catch {}
        do { try await stale.value; XCTFail("Stale destination must fail") } catch {}
        XCTAssertEqual(hardware.starts.map(\.value), [0.2]); XCTAssertTrue(hardware.applied.isEmpty)
    }
}
