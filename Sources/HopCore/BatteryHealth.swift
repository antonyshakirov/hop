import Foundation

public enum BatteryHealth {
    /// Estimates health from battery capacity properties, or returns nil when unavailable.
    public static func percent(properties: [String: Any]) -> Int? {
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        let designValues = [properties["DesignCapacity"], data["DesignCapacity"]]
        let capacityValues = [
            properties["NominalChargeCapacity"], data["NominalChargeCapacity"],
            properties["AppleRawMaxCapacity"], data["AppleRawMaxCapacity"],
            properties["FullChargeCapacity"], data["FullChargeCapacity"]
        ]
        guard let design = positiveCapacity(in: designValues),
              let capacity = positiveCapacity(in: capacityValues) else { return nil }
        return Int(min(100, Double(capacity) / Double(design) * 100).rounded())
    }

    private static func positiveCapacity(in values: [Any?]) -> Int? {
        values.compactMap { $0 as? Int }.first { $0 > 0 }
    }
}
