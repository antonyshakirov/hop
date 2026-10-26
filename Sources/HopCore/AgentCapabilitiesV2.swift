import Foundation

public enum AgentCapabilitiesV2 {
    public static let actionNames = ["timer.start", "timer.pause", "timer.reset", "stopwatch.start", "stopwatch.stop",
                                     "todo.add", "todo.complete", "todo.delete", "tracker.start", "tracker.stop"]
    public static func data() throws -> Data {
        let actions: [[String: Any]] = actionNames.map { name in
            var item: [String: Any] = ["name": name, "requiresCustomerConfirmation": true]
            switch name {
            case "timer.start": item["input"] = ["seconds": ["type": "integer", "minimum": 1, "maximum": 86400]]
            case "todo.add": item["input"] = ["text": ["type": "string", "minLength": 1, "maxLength": 500], "note": ["type": "string", "maxLength": 4000, "optional": true], "important": ["type": "boolean", "optional": true]]
            case "todo.complete", "todo.delete": item["input"] = ["id": ["type": "string", "format": "uuid", "source": "agent-state.json todos[].id"]]
            case "tracker.start": item["input"] = ["task": ["type": "string", "minLength": 1, "maxLength": 500]]
            case "tracker.stop": item["scope"] = "all_active_tracking_sessions"
            default: item["input"] = [String: String]()
            }
            let effects = [
                "timer.start": "Replaces the current timer or stopwatch and clears its progress",
                "timer.pause": "Pauses countdown mode only; rejects stopwatch mode",
                "timer.reset": "Clears countdown progress and work-rest cycle; rejects stopwatch mode",
                "stopwatch.start": "Starts or resumes the stopwatch; running stopwatch is unchanged; rejects a running or paused countdown",
                "stopwatch.stop": "Pauses stopwatch mode only; rejects countdown mode",
                "tracker.stop": "Ends all active tracking sessions",
                "todo.complete": "Completes the exact task UUID from state",
                "todo.delete": "Deletes the exact task UUID from state",
            ]
            if let effect = effects[name] { item["effect"] = effect }
            return item
        }
        let commandSchemas: [[String: Any]] = actions.map { action in
            var properties: [String: Any] = ["do": ["const": action["name"]!]]
            var required = ["do"]
            for (key, value) in action["input"] as? [String: [String: Any]] ?? [:] {
                var property = value
                if property.removeValue(forKey: "optional") as? Bool != true { required.append(key) }
                property.removeValue(forKey: "source")
                properties[key] = property
            }
            return ["type": "object", "additionalProperties": false, "properties": properties, "required": required.sorted()]
        }
        let timestamp: [String: Any] = ["type": "string", "format": "date-time", "pattern": "Z$"]
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": false,
            "required": ["schemaVersion", "id", "createdAt", "expiresAt", "confirmation", "command"],
            "properties": ["schemaVersion": ["const": 2], "id": ["type": "string", "format": "uuid", "pattern": "^[0-9a-f-]{36}$"],
                "createdAt": timestamp, "expiresAt": timestamp,
                "confirmation": ["type": "object", "additionalProperties": false, "required": ["method", "confirmedAt"],
                    "properties": ["method": ["const": "client_agent_attestation"], "confirmedAt": timestamp]],
                "command": ["oneOf": commandSchemas]]
        ]
        let value: [String: Any] = [
            "schemaVersion": 2, "transport": "local_files", "networkListener": false,
            "discoveryFile": "agent-capabilities.json", "stateFile": "agent-state.json",
            "requestDirectory": "agent-requests", "resultDirectory": "agent-results",
            "requestFile": "<lowercase UUID>.json", "maxRequestBytes": 65536, "maxLifetimeSeconds": 600,
            "confirmation": ["method": "client_agent_attestation", "independentlyVerifiesIdentity": false],
            "trustBoundary": "Customer-approved desktop client with OS access to the user's Hop data directory",
            "requestSchema": schema,
            "temporalRule": "createdAt <= confirmedAt <= now < expiresAt; expiresAt-createdAt <= 600 seconds",
            "actions": actions, "statuses": ["applied", "no_change", "rejected", "indeterminate", "conflict"],
            "retry": ["sameId": true, "identicalBytes": true, "uncertainOutcome": "stop_and_inspect_state", "terminalRetentionDays": 30],
            "legacy": ["commandsFile": "agent-commands.json", "protocol": 1, "perCommandResults": false, "safeAutomaticRetries": false]
        ]
        return try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }
}
