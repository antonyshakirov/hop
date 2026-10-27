import Foundation
import CoreFoundation

public enum AgentAudioCommand {
    public struct Settings {
        public let gain: Double?
        public let muted: Bool?
        public let active: Bool?
    }
    public enum Source: String { case system, device, app }
    case volume(SoundDirection, Double)
    case mute(SoundDirection, Bool)
    case device(SoundDirection, String)
    case outputMixer(Bool)
    case application(String, Settings, outputUID: String?)
    case addApplication(String, String)
    case pinApplication(String, Bool)
    case moveApplication(String, Int)
    case resetApplications
    case inputMixer(Bool)
    case inputSource(Source, String?, Settings)

    static func parse(_ command: [String: Any]) throws -> Self {
        let verb = command["do"] as? String ?? ""
        func fields(_ required: Set<String>, _ optional: Set<String> = []) throws {
            let keys = Set(command.keys)
            guard required.union(["do"]).isSubset(of: keys), keys.isSubset(of: required.union(optional).union(["do"])) else { throw AgentProtocolError("invalid_command_fields") }
        }
        func text(_ key: String, limit: Int = 512) throws -> String {
            guard let value = command[key] as? String, !value.isEmpty, value.count <= limit,
                  value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw AgentProtocolError("invalid_audio_identifier") }
            return value
        }
        func boolean(_ key: String) throws -> Bool {
            guard let value = command[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { throw AgentProtocolError("invalid_boolean") }
            return value.boolValue
        }
        func gain(_ key: String) throws -> Double {
            guard let value = command[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
                  (0...1).contains(value.doubleValue) else { throw AgentProtocolError("invalid_audio_gain") }
            return value.doubleValue
        }
        func direction() throws -> SoundDirection {
            guard let value = command["direction"] as? String, let direction = SoundDirection(rawValue: value) else { throw AgentProtocolError("invalid_audio_direction") }
            return direction
        }
        func settings(active: Bool) throws -> Settings {
            let keys: Set<String> = active ? ["gain", "muted", "active"] : ["gain", "muted", "outputUID"]
            guard !keys.isDisjoint(with: command.keys) else { throw AgentProtocolError("empty_audio_update") }
            return try Settings(gain: command["gain"].map { _ in try gain("gain") },
                muted: command["muted"].map { _ in try boolean("muted") }, active: command["active"].map { _ in try boolean("active") })
        }
        switch verb {
        case "audio.master.volume": try fields(["direction", "value"]); return try .volume(direction(), gain("value"))
        case "audio.master.mute": try fields(["direction", "muted"]); return try .mute(direction(), boolean("muted"))
        case "audio.device.select": try fields(["direction", "deviceUID"]); return try .device(direction(), text("deviceUID"))
        case "audio.outputMixer.set": try fields(["enabled"]); return try .outputMixer(boolean("enabled"))
        case "audio.inputMixer.set": try fields(["enabled"]); return try .inputMixer(boolean("enabled"))
        case "audio.app.update":
            try fields(["appID"], ["gain", "muted", "outputUID"])
            return try .application(text("appID", limit: 255), settings(active: false), outputUID: command["outputUID"].map { _ in try text("outputUID") })
        case "audio.app.add": try fields(["appID", "name"]); return try .addApplication(text("appID", limit: 255), text("name", limit: 255))
        case "audio.app.pin": try fields(["appID", "pinned"]); return try .pinApplication(text("appID", limit: 255), boolean("pinned"))
        case "audio.app.move":
            try fields(["appID", "offset"])
            guard let value = command["offset"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), [-1.0, 1.0].contains(value.doubleValue) else { throw AgentProtocolError("invalid_audio_order") }
            return try .moveApplication(text("appID", limit: 255), value.intValue)
        case "audio.app.reset": try fields([]); return .resetApplications
        case "audio.inputSource.update":
            try fields(["source"], ["sourceID", "gain", "muted", "active"])
            guard let raw = command["source"] as? String, let source = Source(rawValue: raw),
                  (source == .system) == (command["sourceID"] == nil) else { throw AgentProtocolError("invalid_audio_source") }
            return try .inputSource(source, command["sourceID"].map { _ in try text("sourceID") }, settings(active: true))
        default: throw AgentProtocolError("unsupported_command")
        }
    }
}
