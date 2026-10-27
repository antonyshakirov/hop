import XCTest
@testable import HopCore

final class AgentAudioProtocolTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func request(_ command: [String: Any], id: UUID = UUID()) throws -> Data {
        let iso = ISO8601DateFormatter()
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "id": id.uuidString.lowercased(),
            "createdAt": iso.string(from: now.addingTimeInterval(-10)), "expiresAt": iso.string(from: now.addingTimeInterval(60)),
            "confirmation": ["method": "client_agent_attestation", "confirmedAt": iso.string(from: now)], "command": command], options: .sortedKeys)
    }
    func testAudioCommandsRequireStrictTypesSourcesAndBoundedValues() throws {
        let valid: [[String: Any]] = [
            ["do": "audio.master.volume", "direction": "output", "value": 0.4],
            ["do": "audio.master.mute", "direction": "input", "muted": true],
            ["do": "audio.device.select", "direction": "output", "deviceUID": "synthetic"],
            ["do": "audio.outputMixer.set", "enabled": false], ["do": "audio.inputMixer.set", "enabled": true],
            ["do": "audio.app.update", "appID": "org.example.synthetic", "gain": 0.2, "outputUID": "system"],
            ["do": "audio.app.add", "appID": "org.example.synthetic", "name": "Synthetic"],
            ["do": "audio.app.pin", "appID": "org.example.synthetic", "pinned": false],
            ["do": "audio.app.move", "appID": "org.example.synthetic", "offset": -1], ["do": "audio.app.reset"],
            ["do": "audio.inputSource.update", "source": "system", "active": false],
            ["do": "audio.inputSource.update", "source": "device", "sourceID": "synthetic", "gain": 0.5],
            ["do": "audio.inputSource.update", "source": "app", "sourceID": "org.example.synthetic", "muted": true]]
        for command in valid { XCTAssertNoThrow(try AgentRequestV2.parse(request(command), now: now), "\(command)") }
        let invalid: [[String: Any]] = [
            ["do": "audio.master.volume", "direction": "output", "value": true],
            ["do": "audio.master.volume", "direction": "output", "value": 1.01],
            ["do": "audio.master.mute", "direction": "input", "muted": 1],
            ["do": "audio.inputMixer.set", "enabled": true, "extra": 1],
            ["do": "audio.app.move", "appID": "org.example.synthetic", "offset": 0],
            ["do": "audio.app.update", "appID": "org.example.synthetic"],
            ["do": "audio.inputSource.update", "source": "device", "active": true],
            ["do": "audio.inputSource.update", "source": "system", "sourceID": "device", "active": true],
            ["do": "audio.inputSource.update", "source": "unknown", "active": true]]
        for command in invalid { XCTAssertThrowsError(try AgentRequestV2.parse(request(command), now: now), "\(command)") }
    }
    @MainActor
    func testDeferredClaimPrecedesEffectDuplicatesDoNotRepeatAndStopIsIndependent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AgentOperationStore(directory: root)
        let data = try request(["do": "audio.inputMixer.set", "enabled": true])
        var finish: ((AgentResultV2) -> Void)?, starts = 0
        try store.processDeferred(data, now: now) { _, completed in
            starts += 1; finish = completed
            let journal = root.appendingPathComponent("agent-journal")
            XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: journal.path).count, 1)
        }
        try store.processDeferred(data, now: now) { _, _ in XCTFail("duplicate start") }
        XCTAssertEqual(starts, 1)
        let results = root.appendingPathComponent("agent-results")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: results.path).count, 0)
        var stopped = false
        try store.processDeferred(request(["do": "audio.inputMixer.set", "enabled": false]), now: now) { _, completed in stopped = true; completed(.applied()) }
        XCTAssertTrue(stopped)
        finish?(.applied())
        let replay = try store.process(data, now: now) { _ in XCTFail("replay"); return .applied() }
        XCTAssertEqual(replay.status, "applied")
    }
    @MainActor
    func testDeferredCrashReplayConflictAndDuplicateCompletionPreserveOriginalClaim() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AgentOperationStore(directory: root), id = UUID()
        let data = try request(["do": "audio.inputMixer.set", "enabled": true], id: id)
        var complete: ((AgentResultV2) -> Void)?
        try store.processDeferred(data, now: now) { _, finish in complete = finish }
        let reopened = try AgentOperationStore(directory: root)
        XCTAssertEqual(try reopened.process(data, now: now) { _ in XCTFail("crash must not restart"); return .applied() }.status, "indeterminate")
        let changed = try request(["do": "audio.inputMixer.set", "enabled": false], id: id)
        try store.processDeferred(changed, now: now) { _, _ in XCTFail("conflict must not run") }
        let receipt = root.appendingPathComponent("agent-results/" + id.uuidString.lowercased() + ".json")
        XCTAssertEqual(try JSONDecoder().decode(AgentResultV2.self, from: Data(contentsOf: receipt)).status, "conflict")
        complete?(.rejected("synthetic_start_failed")); complete?(.applied())
        XCTAssertEqual(try reopened.process(data, now: now) { _ in XCTFail("failure must not retry"); return .applied() }.code, "synthetic_start_failed")
    }
    @MainActor
    func testDeferredExpiredAudioAndCapacityRejectBeforeEffect() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AgentOperationStore(directory: root, capacity: 1)
        let expired = try request(["do": "audio.inputMixer.set", "enabled": true])
        try store.processDeferred(expired, now: now.addingTimeInterval(120)) { _, _ in XCTFail("expired capture") }
        XCTAssertThrowsError(try store.processDeferred(request(["do": "audio.inputMixer.set", "enabled": true]), now: now) { _, _ in XCTFail("over capacity") })
    }

}
