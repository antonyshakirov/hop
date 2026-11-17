import Darwin
import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt

public final class SystemHardwareBackend: HardwareBackend {
    private let fans = SMCFanHardware()
    public init() {}

    public func observe() -> HardwareObservation {
        let sensors = fans.read()
        let power = Self.power()
        return HardwareObservation(fans: sensors.fans, temperature: sensors.temperature,
            supportsControl: sensors.supportsControl, lidClosed: Self.lidClosed(),
            onBattery: power.onBattery, batteryPercent: power.percent,
            thermalSeverity: ProcessInfo.processInfo.thermalState.rawValue)
    }

    public func idleLidReleaseReady() -> Bool { IdleLidPolicy.ready() }

    public func sleepDisabled() throws -> Bool {
        guard let value = Self.parseSleepDisabled(try Self.pmset(["-g"])) else { throw HardwareReason.commandFailed }
        return value
    }

    public func setSleepDisabled(_ disabled: Bool) throws {
        guard geteuid() == 0 else { throw HardwareReason.unauthorized }
        _ = try Self.pmset(["disablesleep", disabled ? "1" : "0"])
        guard try sleepDisabled() == disabled else { throw HardwareReason.commandFailed }
    }

    public func restoreClosedLidBehavior() throws {
        guard geteuid() == 0 else { throw HardwareReason.unauthorized }
        guard try Self.closedLidRequiresSleep() else { return }
        let connection = IOPMFindPowerManagement(kIOMainPortDefault)
        guard connection != 0 else { throw HardwareReason.restoreFailed }
        defer { IOServiceClose(connection) }
        guard try !sleepDisabled() else { throw HardwareReason.restoreFailed }
        // SPEC: a lid opened during restoration must not receive a stale sleep request.
        guard try Self.closedLidRequiresSleep() else { return }
        guard IOPMSleepSystem(connection) == kIOReturnSuccess else { throw HardwareReason.restoreFailed }
    }

    public static func closedLidRequiresSleep(lidClosed: Bool?, causesSleep: Bool?) throws -> Bool {
        guard let lidClosed else { throw HardwareReason.sensor }
        guard lidClosed else { return false }
        guard let causesSleep else { throw HardwareReason.sensor }
        return causesSleep
    }

    private static func closedLidRequiresSleep() throws -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { throw HardwareReason.sensor }
        defer { IOObjectRelease(service) }
        func value(_ key: String) -> Bool? {
            IORegistryEntryCreateCFProperty(service, key as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
        }
        return try closedLidRequiresSleep(lidClosed: value(kAppleClamshellStateKey),
            causesSleep: value(kAppleClamshellCausesSleepKey))
    }

    public func setFans(_ targets: [Int: Double]) throws { try fans.setTargets(targets) }
    public func restoreFans(_ indices: [Int]) throws { try fans.restore(indices: indices) }

    public static func parseSleepDisabled(_ text: String) -> Bool? {
        let lines = text.split(separator: "\n").filter { $0.split(whereSeparator: \.isWhitespace).first == "SleepDisabled" }
        guard lines.count == 1 else { return nil }
        let fields = lines[0].split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, fields[1] == "0" || fields[1] == "1" else { return nil }
        return fields[1] == "1"
    }

    private static func pmset(_ arguments: [String]) throws -> String {
        try HardwareCommand.run("/usr/bin/pmset", arguments: arguments)
    }

    private static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    private static func power() -> (onBattery: Bool?, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let kind = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return (nil, nil) }
        let battery = kind == kIOPSBatteryPowerValue
        var percent: Int?
        if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = values[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = values[kIOPSMaxCapacityKey] as? Int, maximum > 0,
                      current >= 0, current <= maximum else { continue }
                percent = Int((Double(current) / Double(maximum) * 100).rounded(.down))
                break
            }
        }
        return (battery, percent)
    }
}
