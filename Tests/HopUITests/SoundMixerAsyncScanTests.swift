import XCTest
import HopCore
@testable import Hop

private final class ScanGate: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []
    private var gates: [Int: DispatchSemaphore] = [:]
    private var results: [Int: [SoundMixerAppSnapshot]] = [:]

    func block(call: Int) -> DispatchSemaphore {
        lock.lock(); defer { lock.unlock() }
        let gate = DispatchSemaphore(value: 0); gates[call] = gate; return gate
    }
    func result(call: Int, apps: [SoundMixerAppSnapshot]) { lock.lock(); results[call] = apps; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls.count }
    var cleaned: [Bool] { lock.lock(); defer { lock.unlock() }; return calls }

    func scan(_ clean: Bool) -> SoundMixerScan {
        lock.lock(); calls.append(clean); let index = calls.count; let gate = gates[index]; let apps = results[index] ?? []
        lock.unlock()
        gate?.wait()
        return SoundMixerScan(apps: apps, outputs: [])
    }
}

@MainActor
final class SoundMixerAsyncScanTests: XCTestCase {
    private final class Session: SoundMixingSession {
        var stops = 0
        func outputs(_ channels: [SoundMixerChannel]) {}
        func configure(_ channel: SoundMixerChannel) {}
        func stop() { stops += 1 }
    }

    private func app(_ id: String) -> SoundMixerAppSnapshot {
        SoundMixerAppSnapshot(id: id, name: id, processes: [], appRunning: true, sourceRunning: true)
    }

    private func make(_ gate: ScanGate, sessions: @escaping () -> Void = {}) -> (SoundMixerController, UserDefaults, String) {
        let name = "HopTests.AsyncScan." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        let mixer = SoundMixerController(defaults: defaults, makeSession: { _ in sessions(); return Session() },
            scan: { gate.scan($0) })
        return (mixer, defaults, name)
    }

    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testStartShowsStartingUntilScanFinishesThenRuns() async {
        let gate = ScanGate()
        let release = gate.block(call: 1)
        var made = 0
        let (mixer, defaults, name) = make(gate) { made += 1 }
        defer { mixer.stop(); defaults.removePersistentDomain(forName: name) }
        mixer.start()
        XCTAssertTrue(mixer.starting)
        XCTAssertFalse(mixer.running)
        XCTAssertEqual(made, 0)
        release.signal()
        await wait { mixer.running }
        XCTAssertTrue(mixer.running)
        XCTAssertFalse(mixer.starting)
        XCTAssertEqual(made, 1)
    }

    func testStopWhileStartingDiscardsTheLateScan() async {
        let gate = ScanGate()
        let release = gate.block(call: 1)
        var made = 0
        let (mixer, defaults, name) = make(gate) { made += 1 }
        defer { defaults.removePersistentDomain(forName: name) }
        mixer.start()
        mixer.stop()
        XCTAssertFalse(mixer.starting)
        release.signal()
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(mixer.running)
        XCTAssertEqual(made, 0)
    }

    func testStaleScanCannotOverrideANewerRefresh() async {
        let gate = ScanGate()
        let release = gate.block(call: 1)
        gate.result(call: 1, apps: [app("old.app")])
        gate.result(call: 2, apps: [app("new.app")])
        let (mixer, defaults, name) = make(gate)
        defer { mixer.close(); defaults.removePersistentDomain(forName: name) }
        mixer.beginInputObservation()
        mixer.refreshForAgent()
        release.signal()
        await wait { mixer.apps.map(\.id) == ["new.app"] }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(mixer.apps.map(\.id), ["new.app"])
    }

    func testAgentInventoryNeverWaitsForDiscoveryAndFillsFromTheBackground() async {
        let gate = ScanGate()
        let release = gate.block(call: 1)
        gate.result(call: 1, apps: [app("listed.app")])
        let (mixer, defaults, name) = make(gate)
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(mixer.agentApplicationInventory().isEmpty)
        XCTAssertTrue(mixer.agentApplicationInventory().isEmpty)
        release.signal()
        await wait { !mixer.agentApplicationInventory().isEmpty }
        XCTAssertEqual(mixer.agentApplicationInventory().map(\.id), ["listed.app"])
        XCTAssertEqual(gate.count, 1)
    }

    func testMetadataStoreSurvivesConcurrentScans() {
        let store = SoundProcessMetadataStore()
        let launch = Date()
        DispatchQueue.concurrentPerform(iterations: 400) { index in
            let pid = pid_t(index % 20)
            _ = store.value(pid: pid, launch: launch, running: true) {
                SoundMixerAppSnapshot(id: "app.\(pid)", name: "A", processes: [], appRunning: true, sourceRunning: false)
            }
            if index % 7 == 0 { store.retain(Set((0..<10).map { pid_t($0) })) }
        }
    }
}
