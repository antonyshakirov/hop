import Foundation

/// The only operations exposed by the privileged hardware service.
@objc public protocol HardwareXPC {
    func request(_ data: Data, reply: @escaping (Data) -> Void)
}

public enum HardwareReason: String, Codable, Error, Sendable {
    case stopped, battery, thermal, expired, heartbeat, disconnected, sensor
    case unavailable, unsupported, busy, invalid, unauthorized, restoreFailed, commandFailed
    case serviceApproval, serviceMissing, unsignedBuild, protocolMismatch
}

public struct FanReading: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let rpm: Double
    public let minimum: Double
    public let maximum: Double
    public let manual: Bool

    public init(id: Int, rpm: Double, minimum: Double, maximum: Double, manual: Bool) {
        self.id = id; self.rpm = rpm; self.minimum = minimum; self.maximum = maximum; self.manual = manual
    }

    public var valid: Bool {
        (0..<8).contains(id) && rpm.isFinite && minimum.isFinite && maximum.isFinite
            && rpm >= 0 && minimum >= 0 && maximum > minimum && maximum <= 30000
    }
}

public struct FanPolicy: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case automatic, maximum, fixed, curve
    }
    public var mode: Mode
    public var targets: [Int: Double]
    public var cool: Double
    public var hot: Double

    public init(mode: Mode = .automatic, targets: [Int: Double] = [:], cool: Double = 60, hot: Double = 85) {
        self.mode = mode; self.targets = targets; self.cool = cool; self.hot = hot
    }

    public func speeds(for fans: [FanReading], temperature: Double?) throws -> [Int: Double] {
        guard mode != .automatic else { return [:] }
        guard !fans.isEmpty, fans.count <= 8, fans.allSatisfy(\.valid),
              Set(fans.map(\.id)).count == fans.count else { throw HardwareReason.unsupported }
        var fraction: Double = 1
        if mode == .curve {
            guard cool.isFinite, hot.isFinite, (20...110).contains(cool),
                  (25...120).contains(hot), hot - cool >= 5,
                  let temperature, temperature.isFinite, (10...130).contains(temperature)
            else { throw HardwareReason.sensor }
            fraction = max(0, min(1, (temperature - cool) / (hot - cool)))
        }
        if mode == .fixed {
            guard Set(targets.keys) == Set(fans.map(\.id)) else { throw HardwareReason.invalid }
        }
        var output: [Int: Double] = [:]
        for fan in fans {
            let rpm = mode == .fixed ? targets[fan.id]! : fan.minimum + fraction * (fan.maximum - fan.minimum)
            guard rpm.isFinite, (fan.minimum...fan.maximum).contains(rpm) else { throw HardwareReason.invalid }
            output[fan.id] = rpm
        }
        return output
    }
}

public struct HardwareConfiguration: Codable, Equatable, Sendable {
    public var lid: Bool
    public var fan: FanPolicy
    public var duration: Double?

    public init(lid: Bool = false, fan: FanPolicy = .init(), duration: Double? = nil) {
        self.lid = lid; self.fan = fan; self.duration = duration
    }

    public var needsLease: Bool { lid || fan.mode != .automatic }
    public var valid: Bool {
        (duration.map { $0.isFinite && $0 > 0 && $0 <= 8 * 3600 } ?? true)
            && fan.cool.isFinite && fan.hot.isFinite && fan.targets.count <= 8
            && fan.targets.allSatisfy { (0..<8).contains($0.key) && $0.value.isFinite }
    }
}

public struct HardwareRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case status, configure, renew, stop, prepareUpdate, finishUpdate }
    public let version: Int
    public let operation: Operation
    public let configuration: HardwareConfiguration?
    public let transaction: UUID?

    public init(_ operation: Operation, configuration: HardwareConfiguration? = nil, transaction: UUID? = nil) {
        version = 1; self.operation = operation; self.configuration = configuration
        self.transaction = transaction
    }

    public static func decode(_ data: Data) throws -> HardwareRequest {
        guard data.count <= 16384 else { throw HardwareReason.invalid }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1 else { throw HardwareReason.protocolMismatch }
        guard (value.operation == .configure) == (value.configuration != nil),
              ([Operation.prepareUpdate, .finishUpdate].contains(value.operation)) == (value.transaction != nil),
              value.configuration?.valid != false else { throw HardwareReason.invalid }
        return value
    }
}

public struct HardwareStatus: Codable, Equatable, Sendable {
    public var version = 1
    public var fans: [FanReading] = []
    public var temperature: Double?
    public var supportsControl = false
    public var lid = false
    public var policy = FanPolicy()
    public var active = false
    public var restorationPending = false
    public var maintenance = false
    public var maintenanceID: UUID?
    public var reason: HardwareReason?
    public init() {}
}

public struct HardwareObservation: Equatable, Sendable {
    public var fans: [FanReading]
    public var temperature: Double?
    public var temperatureAge: Double
    public var supportsControl: Bool
    public var lidClosed: Bool?
    public var onBattery: Bool?
    public var batteryPercent: Int?
    public var thermalSeverity: Int

    public init(fans: [FanReading] = [], temperature: Double? = nil, temperatureAge: Double = 0,
                supportsControl: Bool = false, lidClosed: Bool? = nil, onBattery: Bool? = nil,
                batteryPercent: Int? = nil, thermalSeverity: Int = 0) {
        self.fans = fans; self.temperature = temperature; self.temperatureAge = temperatureAge
        self.supportsControl = supportsControl; self.lidClosed = lidClosed; self.onBattery = onBattery
        self.batteryPercent = batteryPercent; self.thermalSeverity = thermalSeverity
    }

    public var freshTemperature: Double? {
        temperatureAge.isFinite && (0...10).contains(temperatureAge) ? temperature : nil
    }
}
