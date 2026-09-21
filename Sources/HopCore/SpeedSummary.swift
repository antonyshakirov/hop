import Foundation

/// Reading `networkQuality`'s output. SPEC: docs/spec.md — "Speed test".
public enum SpeedSummary {
    public struct Result: Equatable, Sendable {
        public let down: Double // Mbit/s
        public let up: Double
        public let rpm: Int

        public init(down: Double, up: Double, rpm: Int) {
            self.down = down
            self.up = up
            self.rpm = rpm
        }
    }

    /// The final SUMMARY block; nil when either capacity is missing.
    public static func parse(_ text: String) -> Result? {
        guard let down = lastNumber(in: text, after: "Downlink capacity:"),
              let up = lastNumber(in: text, after: "Uplink capacity:")
        else { return nil }
        return Result(down: down, up: up, rpm: responsiveness(in: text))
    }

    /// The worse of the two scores a sequential run prints, or the single one.
    static func responsiveness(in text: String) -> Int {
        let split = [rpm(in: text, after: "Uplink Responsiveness:"),
                     rpm(in: text, after: "Downlink Responsiveness:")].compactMap { $0 }
        if let worst = split.min() { return worst }
        return rpm(in: text, after: "Responsiveness:") ?? 0
    }

    private static func rpm(in text: String, after marker: String) -> Int? {
        guard let found = text.range(of: marker),
              let match = text[found.upperBound...].range(
                  of: #"(\d+) RPM"#, options: .regularExpression)
        else { return nil }
        return Int(text[match].dropLast(4))
    }

    /// Last number after `marker` — the live lines are redrawn over themselves.
    public static func lastNumber(in text: String, after marker: String) -> Double? {
        var result: Double?
        var search = text.startIndex
        while let found = text.range(of: marker, range: search..<text.endIndex) {
            let tail = text[found.upperBound...].prefix(24)
            let cleaned = tail.trimmingCharacters(in: .whitespaces)
            let numeric = cleaned.prefix { "0123456789.".contains($0) }
            if let value = Double(numeric) { result = value }
            search = found.upperBound
        }
        return result
    }
}
