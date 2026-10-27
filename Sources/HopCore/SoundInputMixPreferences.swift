import Foundation

/// SPEC: product-spec/results/screens/sound-input.md — saved choices never imply capture.
public struct SoundInputMixPreferences: Codable, Equatable, Sendable {
    public var schema = 1
    public var system = SoundChannelSettings()
    public var microphones: [String: SoundChannelSettings] = [:]
    public var applications: [String: SoundChannelSettings] = [:]

    public init() {}

    public static func load(_ data: Data?) -> Self {
        guard let data else { return .init() }
        guard var value = try? JSONDecoder().decode(Self.self, from: data), value.schema == 1 else {
            var closed = Self(); closed.system.active = false
            return closed
        }
        value.system = normalized(value.system)
        value.microphones = value.microphones.mapValues(normalized)
        value.applications = value.applications.filter { SoundCallMixPolicy.allows($0.key) }.mapValues(normalized)
        return value
    }

    public static func allowsMicrophone(_ uid: String) -> Bool {
        !uid.isEmpty && !uid.hasPrefix("com.antonshakirov.hop.audio.")
    }

    public func resolvedInputs(defaultUID: String?, availableUIDs: Set<String>) -> [SoundInputConfiguration] {
        var inputs: [SoundInputConfiguration] = []
        var included: Set<String> = []
        if system.active, let uid = defaultUID, Self.allowsMicrophone(uid), availableUIDs.contains(uid) {
            inputs.append(.init(uid: uid, settings: Self.normalized(system)))
            included.insert(uid)
        }
        for uid in microphones.keys.sorted() {
            guard let settings = microphones[uid], settings.active, Self.allowsMicrophone(uid),
                  availableUIDs.contains(uid), included.insert(uid).inserted else { continue }
            inputs.append(.init(uid: uid, settings: Self.normalized(settings)))
        }
        return inputs
    }

    private static func normalized(_ settings: SoundChannelSettings) -> SoundChannelSettings {
        var result = settings
        result.gain = min(1, result.safeGain); result.bass = false
        return result
    }
}
