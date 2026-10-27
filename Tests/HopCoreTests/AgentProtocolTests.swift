import XCTest
@testable import HopCore

final class AgentProtocolTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func request(id: UUID = UUID(), verb: String = "todo.add", changes: [String: Any] = [:]) throws -> Data {
        let iso = ISO8601DateFormatter()
        var root: [String: Any] = [
            "schemaVersion": 2, "id": id.uuidString.lowercased(),
            "createdAt": iso.string(from: now.addingTimeInterval(-10)),
            "expiresAt": iso.string(from: now.addingTimeInterval(300)),
            "confirmation": ["method": "client_agent_attestation", "confirmedAt": iso.string(from: now.addingTimeInterval(-5))],
            "command": ["do": verb, "text": "Synthetic task"]
        ]
        for (key, value) in changes { root[key] = value }
        return try JSONSerialization.data(withJSONObject: root, options: .sortedKeys)
    }

    func testRequiresExactConfirmationAndValidLifetime() throws {
        XCTAssertNoThrow(try AgentRequestV2.parse(request(), now: now))
        XCTAssertThrowsError(try AgentRequestV2.parse(request(changes: ["confirmation": [:]]), now: now))
        XCTAssertThrowsError(try AgentRequestV2.parse(request(changes: ["expiresAt": "2020-01-01T00:00:00Z"]), now: now))
        XCTAssertThrowsError(try AgentRequestV2.parse(request(changes: ["extra": true]), now: now))
        XCTAssertThrowsError(try AgentRequestV2.parse(request(changes: ["command": ["do": "unknown"]]), now: now))
    }

    func testRetryAndRestartDoNotRepeatTheEffect() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try request(), store = try AgentOperationStore(directory: dir)
        var count = 0
        let first = try store.process(data, now: now) { _ in count += 1; return .applied() }
        XCTAssertEqual(first.status, "applied")
        _ = try store.process(data, now: now) { _ in count += 1; return .applied() }
        let reopened = try AgentOperationStore(directory: dir)
        _ = try reopened.process(data, now: now) { _ in count += 1; return .applied() }
        XCTAssertEqual(count, 1)
    }

    func testChangedBytesConflictWithoutLosingOriginalOutcome() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID(), store = try AgentOperationStore(directory: dir)
        let data = try request(id: id)
        _ = try store.process(data, now: now) { _ in .applied() }
        let conflict = try store.process(request(id: id, changes: ["command": ["do": "timer.pause"]]), now: now) { _ in XCTFail("must not execute"); return .applied() }
        XCTAssertEqual(conflict.status, "conflict")
        let original = try store.process(data, now: now) { _ in XCTFail("must not execute"); return .applied() }
        XCTAssertEqual(original.status, "applied")
    }
    func testUncertainExecutionNeverRetriesAutomatically() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try request(), store = try AgentOperationStore(directory: dir)
        var calls = 0
        let result = try store.process(data, now: now) { _ in calls += 1; throw AgentProtocolError("simulated_crash") }
        XCTAssertEqual(result.status, "indeterminate")
        let next = try AgentOperationStore(directory: dir).process(data, now: now) { _ in calls += 1; return .applied() }
        XCTAssertEqual(next.status, "indeterminate")
        XCTAssertEqual(calls, 1)
    }

    func testRejectsLimitsBooleansAndUnknownFields() throws {
        for command: [String: Any] in [
            ["do": "timer.start", "seconds": true], ["do": "timer.start", "seconds": 1.5],
            ["do": "timer.start", "seconds": 86401], ["do": "timer.start", "seconds": 0],
            ["do": "timer.pause", "extra": true], ["do": "todo.add", "text": "x", "important": 1],
            ["do": "todo.add", "text": String(repeating: "x", count: 501)],
            ["do": "todo.delete", "text": "a guessed name"], ["do": "todo.complete", "id": "not a UUID"]
        ] {
            XCTAssertThrowsError(try AgentRequestV2.parse(request(changes: ["command": command]), now: now))
        }
    }

    func testExpiredRetryKeepsTheAcceptedOutcome() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = try request(), store = try AgentOperationStore(directory: dir)
        _ = try store.process(data, now: now) { _ in .applied() }
        let result = try store.process(data, now: now.addingTimeInterval(3600)) { _ in XCTFail("expired retry"); return .applied() }
        XCTAssertEqual(result.status, "applied")
    }

    func testInboxRejectsSymlinksWithoutReadingOrChangingTheirTarget() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try AgentOperationStore(directory: dir), id = UUID().uuidString.lowercased()
        let target = dir.appendingPathComponent("target.json"), data = try request()
        try data.write(to: target)
        try FileManager.default.createSymbolicLink(at: store.requestsURL.appendingPathComponent(id + ".json"), withDestinationURL: target)
        try store.drain(now: now) { _ in XCTFail("symlink must not execute"); return .applied() }
        XCTAssertEqual(try Data(contentsOf: target), data)
        let receipt = try JSONDecoder().decode(AgentResultV2.self, from: Data(contentsOf: dir.appendingPathComponent("agent-results/" + id + ".json")))
        XCTAssertEqual(receipt.status, "rejected")
    }

    func testDifferentRequestsAreProcessedAndResultsPrivate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try AgentOperationStore(directory: dir), ids = [UUID(), UUID()]
        for id in ids {
            let file = store.requestsURL.appendingPathComponent(id.uuidString.lowercased() + ".json")
            try request(id: id).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        var count = 0
        try store.drain(now: now) { _ in count += 1; return .applied() }
        XCTAssertEqual(count, 2)
        try store.drain(now: now) { _ in count += 1; return .applied() }
        XCTAssertEqual(count, 2)
        for id in ids {
            let p = dir.appendingPathComponent("agent-results/" + id.uuidString.lowercased() + ".json").path
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: p)[.posixPermissions] as? Int, 0o600)
        }
    }

    func testCapacityFailsClosedAndOldTerminalReceiptsCanExpire() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try AgentOperationStore(directory: dir, capacity: 1)
        _ = try store.process(request(), now: now) { _ in .applied() }
        XCTAssertThrowsError(try store.process(request(), now: now) { _ in XCTFail("full journal"); return .applied() })
        _ = try store.process(request(), now: now.addingTimeInterval(31 * 86400)) { _ in XCTFail("expired request"); return .applied() }
    }

    func testChangedMalformedInboxBytesReportConflictWithTheirDigest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try AgentOperationStore(directory: dir), id = UUID()
        let original = try request(id: id)
        _ = try store.process(original, now: now) { _ in .applied() }
        let inbox = store.requestsURL.appendingPathComponent(id.uuidString.lowercased() + ".json")
        for bytes in [Data("malformed".utf8), try request()] {
            try bytes.write(to: inbox, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: inbox.path)
            try store.drain(now: now) { _ in XCTFail("changed bytes must not execute"); return .applied() }
            let result = try JSONDecoder().decode(AgentResultV2.self, from: Data(contentsOf: dir.appendingPathComponent("agent-results/" + id.uuidString.lowercased() + ".json")))
            XCTAssertEqual(result.status, "conflict")
            XCTAssertEqual(result.requestDigest.count, 64)
        }
        XCTAssertEqual(try store.process(original, now: now) { _ in XCTFail("duplicate"); return .applied() }.status, "applied")
    }

    func testFullInboxRejectionStillIdentifiesTheRequestBytes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try AgentOperationStore(directory: dir, capacity: 1), id = UUID()
        _ = try store.process(request(), now: now) { _ in .applied() }
        let file = store.requestsURL.appendingPathComponent(id.uuidString.lowercased() + ".json")
        try request(id: id).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try store.drain(now: now) { _ in XCTFail("full journal"); return .applied() }
        let receipt = try JSONDecoder().decode(AgentResultV2.self, from: Data(contentsOf: dir.appendingPathComponent("agent-results/" + id.uuidString.lowercased() + ".json")))
        XCTAssertEqual(receipt.status, "rejected")
        XCTAssertEqual(receipt.code, "journal_capacity_reached")
        XCTAssertEqual(receipt.requestDigest.count, 64)
    }

    func testUnsafeStorageAndCorruptJournalNeverExecute() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside"), storage = root.appendingPathComponent("storage")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: storage.appendingPathComponent("agent-journal"), withDestinationURL: outside)
        XCTAssertThrowsError(try AgentOperationStore(directory: storage))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
        try FileManager.default.removeItem(at: storage.appendingPathComponent("agent-journal"))
        let store = try AgentOperationStore(directory: storage), id = UUID()
        let journalFile = storage.appendingPathComponent("agent-journal/" + id.uuidString.lowercased() + ".json")
        try Data("damaged journal".utf8).write(to: journalFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalFile.path)
        XCTAssertThrowsError(try store.process(request(id: id), now: now) { _ in XCTFail("corrupt ledger must fail closed"); return .applied() })
    }

    func testFinalJournalWriteFailureStaysIndeterminateAfterRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = root.appendingPathComponent("agent-journal")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: journal.path)
            try? FileManager.default.removeItem(at: root)
        }
        let store = try AgentOperationStore(directory: root), data = try request()
        var effects = 0
        let result = try store.process(data, now: now) { _ in
            effects += 1
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: journal.path)
            return .applied()
        }
        XCTAssertEqual(result.status, "indeterminate")
        let replayed = try AgentOperationStore(directory: root).process(data, now: now) { _ in effects += 1; return .applied() }
        XCTAssertEqual(replayed.status, "indeterminate")
        XCTAssertEqual(effects, 1)
    }

    func testReceiptFailureAfterEffectReplaysStoredResult() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AgentOperationStore(directory: root), id = UUID(), data = try request(id: id)
        let destination = root.appendingPathComponent("agent-results/" + id.uuidString.lowercased() + ".json")
        var effects = 0
        XCTAssertThrowsError(try store.process(data, now: now) { _ in
            effects += 1
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            return .applied()
        })
        try FileManager.default.removeItem(at: destination)
        let result = try AgentOperationStore(directory: root).process(data, now: now) { _ in effects += 1; return .applied() }
        XCTAssertEqual(result.status, "applied")
        XCTAssertEqual(effects, 1)
    }

    func testPublishedSchemaConstructsAcceptedRequestsForEveryAction() throws {
        let capabilities = try JSONSerialization.jsonObject(with: AgentCapabilitiesV2.data()) as! [String: Any]
        let schema = capabilities["requestSchema"] as! [String: Any]
        let properties = schema["properties"] as! [String: Any]
        let commands = (properties["command"] as! [String: Any])["oneOf"] as! [[String: Any]]
        var names = Set<String>()
        for command in commands {
            let fields = command["properties"] as! [String: [String: Any]]
            let name = fields["do"]!["const"] as! String
            names.insert(name)
            var value: [String: Any] = ["do": name]
            for key in command["required"] as! [String] where key != "do" {
                if let choices = fields[key]!["enum"] as? [Any] { value[key] = choices[0] }
                else if fields[key]!["type"] as? String == "boolean" { value[key] = false }
                else if fields[key]!["type"] as? String == "number" { value[key] = 0.5 }
                else if fields[key]!["type"] as? String == "integer" { value[key] = fields[key]!["minimum"] }
                else if fields[key]!["format"] as? String == "uuid" { value[key] = UUID().uuidString }
                else { value[key] = "Synthetic schema task" }
            }
            if ["audio.app.update", "audio.inputSource.update"].contains(name) { value["gain"] = 0.5 }
            XCTAssertNoThrow(try AgentRequestV2.parse(request(changes: ["command": value]), now: now), name)
            value["undeclared"] = true
            XCTAssertThrowsError(try AgentRequestV2.parse(request(changes: ["command": value]), now: now), name)
        }
        XCTAssertEqual(names, Set(AgentCapabilitiesV2.actionNames))
    }

}
