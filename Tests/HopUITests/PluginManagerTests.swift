import XCTest
import HopCore
import HopPluginAPI
@testable import Hop

@MainActor
private final class HeldPluginTransport: PluginRuntimeTransport {
    var didStop: ((PluginError) -> Void)?
    var requests: [PluginRuntimeRequest] = []
    var continuations: [CheckedContinuation<PluginRuntimeReply, Error>] = []
    var stops = 0
    func send(_ request: PluginRuntimeRequest) async throws -> PluginRuntimeReply {
        if request.operation == "unload" { return PluginRuntimeReply(request) }
        requests.append(request)
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func finish(_ result: String = "{}") {
        let index = requests.count - continuations.count
        continuations.removeFirst().resume(returning: PluginRuntimeReply(requests[index], result: Data(result.utf8)))
    }
    func fail() { continuations.removeFirst().resume(throwing: PluginError.runtimeStopped) }
    func stop() { stops += 1 }
}

@MainActor
final class PluginManagerTests: XCTestCase {
    var directory: URL!
    override func setUp() { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    override func tearDown() { Theme.pluginOverlay = nil; try? FileManager.default.removeItem(at: directory) }
    let bytes = Data(#"{"formatVersion":1,"manifest":{"id":"example","version":"1.0.0","apiVersion":1,"name":"Example","description":"Example","author":"Example","capabilities":["ui.theme","ui.panel","timer.control"],"settings":[]},"code":"definePlugin({})"}"#.utf8)
    func settle(_ condition: @escaping () -> Bool) async throws {
        let end = Date().addingTimeInterval(3)
        while !condition(), Date() < end { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition())
    }
    private func make() -> (PluginManager, HeldPluginTransport, TimerEngine) {
        let timer = TimerEngine(), transport = HeldPluginTransport()
        return (PluginManager(engine: timer, directory: directory, transport: transport), transport, timer)
    }
    func testAllOffDoesNoRuntimeWorkAndApprovalIsExactDigest() async throws {
        let (manager, transport, _) = make()
        manager.install(bytes, origin: "local"); manager.start()
        XCTAssertTrue(transport.requests.isEmpty)
        let record = try XCTUnwrap(manager.records.first)
        manager.approve(record.id, digest: "wrong", capabilities: record.grantedCapabilities)
        XCTAssertTrue(transport.requests.isEmpty)
        manager.approve(record.id, digest: record.digest, capabilities: Set(record.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        transport.finish()
        try await settle { manager.active.contains(record.id) }
        manager.disable(record.id)
        XCTAssertTrue(manager.active.isEmpty)
        XCTAssertNil(manager.panel)
    }
    func testLateReplyAfterDisableCannotRestoreOverlayOrRunCommand() async throws {
        let (manager, transport, timer) = make()
        manager.install(bytes, origin: "local")
        let r = try XCTUnwrap(manager.records.first)
        manager.approve(r.id, digest: r.digest, capabilities: Set(r.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        manager.disable(r.id)
        transport.finish(##"{"commands":[{"type":"timer.start","seconds":60}],"theme":{"dark":{"accent":"#00ff00"}}}"##)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(timer.state, .idle)
        XCTAssertNil(Theme.pluginOverlay)
    }
    func testManualTimerChangeWinsAndInvalidDescriptorHasNoPartialEffect() async throws {
        let (manager, transport, timer) = make()
        manager.install(bytes, origin: "local")
        let r = try XCTUnwrap(manager.records.first)
        manager.approve(r.id, digest: r.digest, capabilities: Set(r.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        timer.setPreset(minutes: 10)
        transport.finish(#"{"commands":[{"type":"timer.start","seconds":60}]}"#)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(timer.state, .idle)
        XCTAssertEqual(timer.duration, 600)
        XCTAssertTrue(manager.active.contains(r.id))
        manager.disable(r.id)
        manager.approve(r.id, digest: r.digest, capabilities: Set(r.package.manifest.capabilities))
        try await settle { transport.requests.count == 2 }
        transport.finish(#"{"commands":[{"type":"timer.start","seconds":60}],"panel":{"mode":"replace","nodes":[{"type":"shell"}]}}"#)
        try await settle { manager.records.first?.quarantinedDigest != nil }
        XCTAssertEqual(timer.state, .idle)
        XCTAssertEqual(timer.duration, 600)
    }
    func testRuntimeFailurePausesWithoutRetryAndRetainsSelection() async throws {
        let (manager, transport, _) = make()
        manager.install(bytes, origin: "local")
        let r = try XCTUnwrap(manager.records.first)
        manager.approve(r.id, digest: r.digest, capabilities: Set(r.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        transport.fail()
        try await settle { manager.records.first?.quarantinedDigest == r.digest }
        XCTAssertTrue(manager.records[0].wantedEnabled)
        XCTAssertTrue(manager.active.isEmpty)
        manager.start()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertFalse(try PluginStore(directory: directory).state.records[0].canRun)
    }

    func testUnexpectedIdleMemoryFailureImmediatelyRemovesOverlaysAndKeepsSettings() async throws {
        let (manager, transport, _) = make()
        manager.install(bytes, origin: "local")
        let r = try XCTUnwrap(manager.records.first)
        manager.approve(r.id, digest: r.digest, capabilities: Set(r.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        transport.finish(##"{"theme":{"dark":{"accent":"#00ff00"}},"panel":{"mode":"replace","nodes":[{"type":"text","text":"Native"}]}}"##)
        try await settle { manager.panel != nil }
        transport.didStop?(.memoryLimit)
        XCTAssertNil(manager.panel)
        XCTAssertNil(Theme.pluginOverlay)
        XCTAssertEqual(manager.error, PluginError.memoryLimit.rawValue)
        XCTAssertTrue(manager.records[0].wantedEnabled)
        XCTAssertTrue(manager.active.isEmpty)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testLateNativeExitReasonEnrichesGenericFailureAfterSessionsAreCleared() async throws {
        for reason in [PluginError.memoryLimit, .deadlineExceeded] {
            let (manager, transport, _) = make()
            manager.install(bytes, origin: "local")
            let record = try XCTUnwrap(manager.records.first)
            manager.approve(record.id, digest: record.digest, capabilities: Set(record.package.manifest.capabilities))
            try await settle { transport.requests.count == 1 }
            transport.finish()
            try await settle { manager.active.contains(record.id) }
            transport.didStop?(.runtimeStopped)
            XCTAssertTrue(manager.active.isEmpty)
            XCTAssertEqual(manager.error, PluginError.runtimeStopped.rawValue)
            transport.didStop?(reason)
            XCTAssertEqual(manager.error, reason.rawValue)
            XCTAssertEqual(transport.requests.count, 1)
            XCTAssertEqual(transport.stops, 1)
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testLateExitAfterExplicitDisableDoesNotPauseAnInertRuntime() async throws {
        let (manager, transport, _) = make()
        manager.install(bytes, origin: "local")
        let record = try XCTUnwrap(manager.records.first)
        manager.approve(record.id, digest: record.digest, capabilities: Set(record.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        transport.finish()
        try await settle { manager.active.contains(record.id) }
        manager.disableAll()
        transport.didStop?(.memoryLimit)
        XCTAssertNil(manager.error)
        XCTAssertEqual(transport.stops, 0)
    }

    func testDisableRevokesLiveSessionEvenWhenSettingsCannotBeSaved() async throws {
        let (manager, transport, _) = make()
        manager.install(bytes, origin: "local")
        let r = try XCTUnwrap(manager.records.first)
        manager.approve(r.id, digest: r.digest, capabilities: Set(r.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        transport.finish(##"{"theme":{"dark":{"accent":"#00ff00"}},"panel":{"mode":"replace","nodes":[{"type":"text","text":"Native"}]}}"##)
        try await settle { manager.panel != nil }
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        manager.disable(r.id)
        XCTAssertTrue(manager.active.isEmpty)
        XCTAssertNil(manager.panel)
        XCTAssertNil(Theme.pluginOverlay)
        XCTAssertEqual(manager.error, PluginError.storageFailure.rawValue)
    }
    func testZeroGrantPluginScalarCommandsAreQuarantinedWithoutCrashingHost() async throws {
        let (manager, transport, timer) = make()
        var value = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        var manifest = value["manifest"] as! [String: Any]
        manifest["capabilities"] = [String]()
        value["manifest"] = manifest
        manager.install(try JSONSerialization.data(withJSONObject: value), origin: "local")
        let r = try XCTUnwrap(manager.records.first)
        manager.approve(r.id, digest: r.digest, capabilities: [])
        try await settle { transport.requests.count == 1 }
        transport.finish(#"{"commands":42}"#)
        try await settle { manager.records[0].quarantinedDigest == r.digest }
        XCTAssertTrue(manager.active.isEmpty)
        XCTAssertEqual(timer.state, .idle)
    }
    func testUnavailableRuntimeDoesNotQuarantineAnInnocentPackage() async throws {
        let (manager, transport, _) = make()
        manager.install(bytes, origin: "local")
        let r = try XCTUnwrap(manager.records.first)
        manager.approve(r.id, digest: r.digest, capabilities: Set(r.package.manifest.capabilities))
        try await settle { transport.requests.count == 1 }
        transport.continuations.removeFirst().resume(throwing: PluginError.runtimeUnavailable)
        try await settle { manager.error == PluginError.runtimeUnavailable.rawValue }
        XCTAssertNil(manager.records[0].quarantinedDigest)
        XCTAssertTrue(manager.records[0].wantedEnabled)
        XCTAssertTrue(manager.active.isEmpty)
    }
}
