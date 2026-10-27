import Foundation

public enum AgentCapabilitiesV2 {
    public static let actionNames = ["timer.start", "timer.pause", "timer.reset", "stopwatch.start", "stopwatch.stop",
                                     "todo.add", "todo.complete", "todo.delete", "tracker.start", "tracker.stop"] + audioActions.keys.sorted()
    private static let audioActions: [String: [String: [String: Any]]] = {
        let direction: [String: Any] = ["type": "string", "enum": ["input", "output"]]
        let identifier: [String: Any] = ["type": "string", "minLength": 1, "maxLength": 512, "pattern": "^\\S(?:[^\\x00-\\x1f]*\\S)?$"]
        let app: [String: Any] = ["type": "string", "minLength": 1, "maxLength": 255]
        let gain: [String: Any] = ["type": "number", "minimum": 0, "maximum": 1]
        let boolean: [String: Any] = ["type": "boolean"]
        func optional(_ input: [String: Any]) -> [String: Any] { input.merging(["optional": true]) { _, new in new } }
        return [
            "audio.master.volume": ["direction": direction, "value": gain],
            "audio.master.mute": ["direction": direction, "muted": boolean],
            "audio.device.select": ["direction": direction, "deviceUID": identifier],
            "audio.outputMixer.set": ["enabled": boolean], "audio.inputMixer.set": ["enabled": boolean],
            "audio.app.update": ["appID": app, "gain": optional(gain), "muted": optional(boolean), "outputUID": optional(identifier)],
            "audio.app.add": ["appID": app, "name": app], "audio.app.pin": ["appID": app, "pinned": boolean],
            "audio.app.move": ["appID": app, "offset": ["type": "integer", "minimum": -1, "maximum": 1, "enum": [-1, 1]]],
            "audio.app.reset": [:],
            "audio.inputSource.update": ["source": ["type": "string", "enum": ["system", "device", "app"]], "sourceID": optional(identifier),
                "gain": optional(gain), "muted": optional(boolean), "active": optional(boolean)]
        ]
    }()
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
            if let input = audioActions[name] { item["input"] = input; item["effect"] = name == "audio.inputMixer.set" ? "Explicit capture start waits for session ready; stop cancels pending start" : "Changes audio controls or saved source settings; enabled output session does not prove audible playback" }
            if name == "audio.app.reset" { item["scope"] = "all_application_audio_preferences"; item["effect"] = "Resets app gains, mutes and destinations; preserves pins and order" }
            if name == "audio.inputSource.update" { item["effect"] = "Saves source settings while stopped; live edits may request microphone permission and wait for configuration acknowledgement" }
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
            var schema: [String: Any] = ["type": "object", "additionalProperties": false, "properties": properties, "required": required.sorted()]
            if action["name"] as? String == "audio.app.update" { schema["anyOf"] = ["gain", "muted", "outputUID"].map { ["required": [$0]] } }
            if action["name"] as? String == "audio.inputSource.update" {
                schema["allOf"] = [["anyOf": ["gain", "muted", "active"].map { ["required": [$0]] }],
                    ["if": ["properties": ["source": ["const": "system"]]], "then": ["not": ["required": ["sourceID"]]], "else": ["required": ["sourceID"]]]]
            }
            return schema
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
