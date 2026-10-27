import Foundation

public struct SoundChannelSettings: Codable, Equatable, Sendable {
    public var gain: Double = 1
    public var muted = false
    public var bass = false
    public var active = true
    public init() {}
    public var safeGain: Double { gain.isFinite ? min(2, max(0, gain)) : 1 }
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
    public var apps: [SoundApplicationConfiguration]?
    public var requestID: UInt64?
    public var captureToken: String?
    public var microphoneMuted: Bool?
    public init(start: Bool = false, meters: Bool = false, inputs: [SoundInputConfiguration] = [],
                apps: [SoundApplicationConfiguration] = [], requestID: UInt64? = nil, captureToken: String? = nil,
                microphoneMuted: Bool? = nil) {
        self.start = start; self.meters = meters; self.inputs = inputs
        self.apps = apps; self.requestID = requestID; self.captureToken = captureToken
        self.microphoneMuted = microphoneMuted
    }
}

public struct SoundApplicationConfiguration: Codable, Equatable, Sendable {
    public var id: String
    public var processes: [UInt32]
    public var settings: SoundChannelSettings
    public init(id: String, processes: [UInt32], settings: SoundChannelSettings) {
        self.id = id; self.processes = processes; self.settings = settings
    }
}

public enum SoundCallMixPolicy {
    public static func ownsProcess(_ processBundle: String, selectedBundle: String) -> Bool {
        allows(selectedBundle) && (processBundle == selectedBundle || processBundle.hasPrefix(selectedBundle + "."))
    }

    public static func allows(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && !["us.zoom", "com.antonshakirov.minimo", "com.antonshakirov.hop"]
            .contains { bundleID.hasPrefix($0) }
    }
}
