import Foundation
import CoreFoundation

public struct AgentProtocolError: Error, Equatable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

public struct AgentRequestV2 {
    public enum Command {
        case legacy(AgentCommand)
        case completeTodo(UUID)
        case deleteTodo(UUID)
        case audio(AgentAudioCommand)
    }
    public let id: UUID
    public let command: Command

    public static func identifier(_ data: Data) throws -> UUID {
        guard data.count <= 65_536,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["id"] as? String, let id = UUID(uuidString: text),
              text == id.uuidString.lowercased() else { throw AgentProtocolError("invalid_request_id") }
        return id
    }

    public static func parse(_ data: Data, now: Date) throws -> AgentRequestV2 {
        let id = try identifier(data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["schemaVersion", "id", "createdAt", "expiresAt", "confirmation", "command"],
              integer(root["schemaVersion"], range: 2...2) != nil,
              let created = date(root["createdAt"]), let expires = date(root["expiresAt"]),
              created <= now, expires > now, expires > created, expires.timeIntervalSince(created) <= 600,
              let approval = root["confirmation"] as? [String: Any],
              Set(approval.keys) == ["method", "confirmedAt"],
              approval["method"] as? String == "client_agent_attestation",
              let confirmed = date(approval["confirmedAt"]), confirmed >= created, confirmed <= now,
              let command = root["command"] as? [String: Any], let verb = command["do"] as? String
        else { throw AgentProtocolError("invalid_confirmation_or_lifetime") }
        let parsed: Command
        switch verb {
        case "timer.start":
            try fields(command, required: ["do", "seconds"])
            guard let seconds = integer(command["seconds"], range: 1...86_400) else { throw AgentProtocolError("invalid_duration") }
            parsed = .legacy(.timerStart(seconds: seconds))
        case "timer.pause", "timer.reset", "stopwatch.start", "stopwatch.stop", "tracker.stop":
            try fields(command, required: ["do"])
            let verbs: [String: AgentCommand] = ["timer.pause": .timerPause, "timer.reset": .timerReset,
                "stopwatch.start": .stopwatchStart, "stopwatch.stop": .stopwatchStop, "tracker.stop": .trackerStop]
            parsed = .legacy(verbs[verb]!)
        case "todo.add":
            try fields(command, required: ["do", "text"], optional: ["note", "important"])
            let text = try string(command["text"], limit: 500)
            let note = try command["note"].map { try string($0, limit: 4_000, empty: true) } ?? ""
            if let important = command["important"] {
                guard let n = important as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw AgentProtocolError("invalid_boolean") }
            }
            parsed = .legacy(.todoAdd(.init(text: text, note: note, important: command["important"] as? Bool ?? false)))
        case "todo.complete", "todo.delete":
            try fields(command, required: ["do", "id"])
            guard let text = command["id"] as? String, let target = UUID(uuidString: text) else { throw AgentProtocolError("invalid_todo_id") }
            parsed = verb == "todo.complete" ? .completeTodo(target) : .deleteTodo(target)
        case "tracker.start":
            try fields(command, required: ["do", "task"])
            parsed = .legacy(.trackerStart(task: try string(command["task"], limit: 500)))
        default:
            parsed = .audio(try AgentAudioCommand.parse(command))
        }
        return AgentRequestV2(id: id, command: parsed)
    }

    private static func fields(_ value: [String: Any], required: Set<String>, optional: Set<String> = []) throws {
        let keys = Set(value.keys)
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw AgentProtocolError("invalid_command_fields") }
    }
    private static func integer(_ value: Any?, range: ClosedRange<Int>) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value, value >= Double(range.lowerBound), value <= Double(range.upperBound) else { return nil }
        return Int(value)
    }
    private static func string(_ value: Any?, limit: Int, empty: Bool = false) throws -> String {
        guard let text = value as? String else { throw AgentProtocolError("invalid_text") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (empty || !trimmed.isEmpty), trimmed.count <= limit else { throw AgentProtocolError("invalid_text") }
        return trimmed
    }
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, text.hasSuffix("Z") else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        return iso.date(from: text)
    }
}

public struct AgentResultV2: Codable, Equatable {
    public var schemaVersion = 2
    public var id = ""
    public var requestDigest = ""
    public let status: String
    public let code: String
    public var entityIDs: [String] = []

    public static func applied(ids: [UUID] = []) -> AgentResultV2 {
        AgentResultV2(status: "applied", code: "applied_to_current_session", entityIDs: ids.map { $0.uuidString.lowercased() })
    }
    public static func noChange() -> AgentResultV2 { AgentResultV2(status: "no_change", code: "already_in_requested_state") }
    public static func rejected(_ code: String) -> AgentResultV2 { AgentResultV2(status: "rejected", code: code) }
    public static func indeterminate() -> AgentResultV2 { AgentResultV2(status: "indeterminate", code: "execution_unconfirmed") }
    public static func conflict() -> AgentResultV2 { AgentResultV2(status: "conflict", code: "request_id_reused") }
}
