import Foundation
import IOKit
import IOKit.pwr_mgt

// SPEC: docs/spec.md — Independent lid mode, ordinary idle release.
enum IdleLidPolicy {
    static let blockingAssertions = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep"]
    private static let nonblockingAssertions: Set<String> = ["EnableIdleSleep", "PreventDiskIdle"]

    static func unblocked(_ assertions: [String: Int]?) -> Bool {
        guard let assertions, blockingAssertions.allSatisfy({ assertions[$0] != nil }) else { return false }
        return assertions.allSatisfy { key, value in
            value >= 0 && (value == 0 || nonblockingAssertions.contains(key))
        }
    }

    static func eligible(idleSeconds: Double?, sleepMinutes: Double?, assertions: [String: Int]?) -> Bool {
        guard let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0,
              let sleepMinutes, sleepMinutes.isFinite, sleepMinutes > 0,
              sleepMinutes <= Double(Int32.max), idleSeconds >= sleepMinutes * 60,
              unblocked(assertions) else { return false }
        return true
    }

    static func sleepMinutes(_ text: String) -> Double? {
        let values = text.split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace) }
            .filter { $0.first == "sleep" }
        guard values.count == 1, values[0].count >= 2 else { return nil }
        return Double(values[0][1])
    }

    static func ready() -> Bool {
        guard unblocked(assertions()),
              let settings = try? HardwareCommand.run("/usr/bin/pmset", arguments: ["-g"]),
              let after = assertions() else { return false }
        return eligible(idleSeconds: idleSeconds(), sleepMinutes: sleepMinutes(settings), assertions: after)
    }

    private static func assertions() -> [String: Int]? {
        var values: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&values) == kIOReturnSuccess,
              let values = values?.takeRetainedValue() as? [String: Any] else { return nil }
        return levels(values)
    }

    static func levels(_ raw: [String: Any]) -> [String: Int]? {
        var result: [String: Int] = [:]
        for (key, value) in raw {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let level = number.doubleValue
            guard level.isFinite, level.rounded() == level, (0...255).contains(level) else { return nil }
            result[key] = Int(level)
        }
        return result
    }

    private static func idleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber else { return nil }
        return value.doubleValue / 1_000_000_000
    }
}
