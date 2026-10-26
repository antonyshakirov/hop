import Foundation
import XCTest
import HopCore
@testable import Hop

@MainActor
final class AgentBridgeV2Tests: XCTestCase {
    private func request(_ command: [String: Any], id: UUID = UUID(), now: Date) throws -> Data {
        let iso = ISO8601DateFormatter()
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2, "id": id.uuidString.lowercased(),
            "createdAt": iso.string(from: now.addingTimeInterval(-10)),
            "expiresAt": iso.string(from: now.addingTimeInterval(300)),
            "confirmation": ["method": "client_agent_attestation", "confirmedAt": iso.string(from: now.addingTimeInterval(-5))],
            "command": command
        ], options: .sortedKeys)
    }

    func testConfirmedTaskAndTimerAcrossRetryAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(preview: true), bridge = AgentBridge(directory: root), now = Date()
        let count = model.todos.list.items.count
        let add = try request(["do": "todo.add", "text": "Synthetic agent task"], now: now)
        let store = try AgentOperationStore(directory: root)
        let result = try store.process(add, now: now) { bridge.performConfirmed($0, on: model) }
        XCTAssertEqual(result.status, "applied")
        XCTAssertEqual(result.entityIDs.count, 1)
        XCTAssertEqual(model.todos.list.items.count, count + 1)
        _ = try AgentOperationStore(directory: root).process(add, now: now) { bridge.performConfirmed($0, on: model) }
        XCTAssertEqual(model.todos.list.items.count, count + 1)
        let timer = try request(["do": "timer.start", "seconds": 1500], now: now)
        let started = try store.process(timer, now: now) { bridge.performConfirmed($0, on: model) }
        XCTAssertEqual(started.status, "applied")
        XCTAssertEqual(model.engine.duration, 1500)
        XCTAssertEqual(model.engine.state, .running)
        model.engine.pause()
    }

    func testCompletionUsesTheExactIdentityAndRejectsUnknownID() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(preview: true), bridge = AgentBridge(directory: root), now = Date()
        let first = model.todos.add(text: "Same synthetic title")!, second = model.todos.add(text: "Same synthetic title")!
        let command = try AgentRequestV2.parse(request(["do": "todo.complete", "id": second.uuidString], now: now), now: now)
        XCTAssertEqual(bridge.performConfirmed(command, on: model).status, "applied")
        XCTAssertEqual(model.todos.list.items.first { $0.id == first }?.done, false)
        XCTAssertEqual(model.todos.list.items.first { $0.id == second }?.done, true)
        XCTAssertEqual(bridge.performConfirmed(command, on: model).status, "no_change")
        let unknown = try AgentRequestV2.parse(request(["do": "todo.delete", "id": UUID().uuidString], now: now), now: now)
        XCTAssertEqual(bridge.performConfirmed(unknown, on: model).code, "todo_not_found")
    }
    func testWatchedInboxPublishesTheActualTaskAndReceipt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(preview: true), bridge = AgentBridge(directory: root), now = Date(), id = UUID()
        bridge.start(model: model)
        let capabilities = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("agent-capabilities.json"))) as! [String: Any]
        XCTAssertEqual(capabilities["schemaVersion"] as? Int, 2)
        let file = root.appendingPathComponent("agent-requests/" + id.uuidString.lowercased() + ".json")
        try request(["do": "todo.add", "text": "Synthetic watched task"], id: id, now: now).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let result = root.appendingPathComponent("agent-results/" + id.uuidString.lowercased() + ".json")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: result.path) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let receipt = try JSONDecoder().decode(AgentResultV2.self, from: Data(contentsOf: result))
        XCTAssertEqual(receipt.status, "applied")
        XCTAssertEqual(model.todos.list.items.filter { $0.text == "Synthetic watched task" }.count, 1)
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("agent-state.json"))) as! [String: Any]
        let todos = snapshot["todos"] as! [[String: Any]]
        XCTAssertEqual(todos.filter { $0["text"] as? String == "Synthetic watched task" }.count, 1)
    }

    func testClockCommandsRespectModeAndPreserveAnExistingStopwatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(preview: true), bridge = AgentBridge(directory: root), now = Date()
        func send(_ value: [String: Any]) throws -> AgentResultV2 {
            bridge.performConfirmed(try AgentRequestV2.parse(request(value, now: now), now: now), on: model)
        }
        model.engine.reset()
        model.engine.setStopwatch(true)
        model.engine.start()
        XCTAssertEqual(try send(["do": "timer.pause"]).status, "rejected")
        XCTAssertEqual(try send(["do": "timer.reset"]).status, "rejected")
        XCTAssertEqual(model.engine.state, .running)
        XCTAssertEqual(try send(["do": "stopwatch.start"]).status, "no_change")
        XCTAssertEqual(try send(["do": "timer.start", "seconds": 90]).status, "applied")
        XCTAssertFalse(model.engine.isStopwatch)
        XCTAssertEqual(model.engine.duration, 90)
        XCTAssertEqual(model.engine.state, .running)
        XCTAssertEqual(try send(["do": "stopwatch.stop"]).status, "rejected")
        XCTAssertEqual(try send(["do": "stopwatch.start"]).status, "rejected")
        XCTAssertEqual(model.engine.state, .running)
        model.engine.pause()
        XCTAssertEqual(try send(["do": "stopwatch.start"]).status, "rejected")
        model.engine.reset()
        XCTAssertEqual(try send(["do": "stopwatch.start"]).status, "applied")
        XCTAssertTrue(model.engine.isStopwatch)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(try send(["do": "stopwatch.stop"]).status, "applied")
        let heldElapsed = model.engine.elapsed
        XCTAssertGreaterThan(heldElapsed, 0)
        XCTAssertEqual(try send(["do": "stopwatch.start"]).status, "applied")
        XCTAssertGreaterThanOrEqual(model.engine.elapsed, heldElapsed)
        XCTAssertEqual(model.engine.state, .running)
        model.engine.pause()
    }

}
