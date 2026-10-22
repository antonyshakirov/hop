import Foundation

public struct SoundChannelSettings: Codable, Equatable, Sendable {
    public var gain: Double = 1
    public var muted = false
    public var bass = false
    public var active = true
    public init() {}
    public var safeGain: Double { gain.isFinite ? min(2, max(0, gain)) : 1 }
}

public enum SoundMixerActivity {
    public static func requiresProcessing(apps: [SoundChannelSettings], inputs: [SoundChannelSettings]) -> Bool {
        func adjusted(_ channel: SoundChannelSettings) -> Bool {
            channel.muted || abs(channel.safeGain - 1) > 0.000001
        }
        let activeInputs = inputs.filter(\.active)
        return apps.contains { $0.active && adjusted($0) }
            || activeInputs.count > 1
            || activeInputs.contains { $0.bass || adjusted($0) }
    }
}

public struct SoundInputConfiguration: Codable, Equatable, Sendable {
    public var uid: String
    public var settings: SoundChannelSettings
    public init(uid: String, settings: SoundChannelSettings) {
        self.uid = uid; self.settings = settings
    }
}

public struct SoundWorkerCommand: Codable, Sendable {
    public var start: Bool
    public var meters: Bool
    public var inputs: [SoundInputConfiguration]
    public init(start: Bool = false, meters: Bool = false, inputs: [SoundInputConfiguration] = []) {
        self.start = start; self.meters = meters; self.inputs = inputs
    }
}
