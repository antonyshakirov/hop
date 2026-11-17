import Darwin
import Foundation

// SPEC: docs/spec.md — Cooling controls. SMC transport provenance is in SMC.swift.
public final class SMCFanHardware: @unchecked Sendable {
    private enum Control { case appleSilicon, intel, unsupported }
    private let transport: SMCTransport?
    private let canWrite: () -> Bool
    private let lock = NSLock()
    private var temperatureKeys: [String]?

    public convenience init() { self.init(transport: SMC(), canWrite: { geteuid() == 0 }) }
    init(transport: SMCTransport?, canWrite: @escaping () -> Bool) {
        self.transport = transport; self.canWrite = canWrite
    }

    public func read() -> (fans: [FanReading], temperature: Double?, supportsControl: Bool) {
        lock.lock(); defer { lock.unlock() }
        let inventory = inventory()
        guard let transport else { return ([], nil, false) }
        if temperatureKeys == nil {
            let keys = (0..<transport.keyCount()).compactMap { transport.key(at: $0) }
                .filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
            temperatureKeys = keys.isEmpty ? ["TC0P", "TC0D", "TC0E", "TC0F", "TCAD", "TCXC"] : keys
        }
        let temperatures = (temperatureKeys ?? []).compactMap { transport.read($0)?.number }
            .filter { $0.isFinite && (10...130).contains($0) }
        return (inventory.fans, temperatures.isEmpty ? nil
            : temperatures.reduce(0, +) / Double(temperatures.count), inventory.control != .unsupported)
    }

    public func setTargets(_ targets: [Int: Double]) throws {
        lock.lock(); defer { lock.unlock() }
        guard canWrite(), let transport else { throw HardwareReason.unauthorized }
        let inventory = inventory()
        guard inventory.control != .unsupported,
              Set(targets.keys) == Set(inventory.fans.map(\.id)),
              inventory.fans.allSatisfy({ fan in
                  targets[fan.id].map { $0.isFinite && (fan.minimum...fan.maximum).contains($0) } == true
              }) else { throw HardwareReason.unsupported }
        switch inventory.control {
        case .appleSilicon:
            let usesTestKey = transport.type(of: "Ftst") == "ui8 "
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while true {
                do {
                    if usesTestKey && transport.read("Ftst")?.number != 1 {
                        try transport.write("Ftst", bytes: [1])
                    }
                    for fan in inventory.fans where transport.read(inventory.modes[fan.id]!)?.number != 1 {
                        try transport.write(inventory.modes[fan.id]!, bytes: [1])
                    }
                } catch {
                    // SPEC: temporary firmware rejection may yield within the bounded takeover window.
                }
                if inventory.modes.values.allSatisfy({ transport.read($0)?.number == 1 }),
                   !usesTestKey || transport.read("Ftst")?.number == 1 { break }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw HardwareReason.commandFailed }
                Thread.sleep(forTimeInterval: 0.1)
            }
        case .intel:
            guard let value = transport.read("FS! ")?.number,
                  value.isFinite, (0...65535).contains(value) else { throw HardwareReason.commandFailed }
            let mask = inventory.fans.reduce(UInt16(value)) { $0 | (UInt16(1) << $1.id) }
            try transport.write("FS! ", bytes: [UInt8(mask >> 8), UInt8(mask & 255)])
            guard transport.read("FS! ")?.number == Double(mask) else { throw HardwareReason.commandFailed }
        case .unsupported: throw HardwareReason.unsupported
        }
        for fan in inventory.fans {
            let rpm = targets[fan.id]!
            let bytes: [UInt8]
            if inventory.control == .appleSilicon {
                bytes = withUnsafeBytes(of: Float(rpm)) { Array($0) }
            } else {
                let value = UInt16((rpm * 4).rounded())
                bytes = [UInt8(value >> 8), UInt8(value & 255)]
            }
            try transport.write("F\(fan.id)Tg", bytes: bytes)
            guard let actual = transport.read("F\(fan.id)Tg")?.number,
                  actual.isFinite, abs(actual - rpm) <= 1 else { throw HardwareReason.commandFailed }
        }
    }

    public func restore(indices: [Int]) throws {
        lock.lock(); defer { lock.unlock() }
        guard !indices.isEmpty else { return }
        guard canWrite(), let transport, indices.count <= 8, Set(indices).count == indices.count,
              indices.allSatisfy({ (0..<8).contains($0) }) else { throw HardwareReason.unauthorized }
        var failed = false
        let modes = Dictionary(uniqueKeysWithValues: indices.compactMap { index in
            modeKey(index).map { (index, $0) }
        })
        let apple = modes.count == indices.count && indices.allSatisfy {
            transport.type(of: "F\($0)Tg") == "flt "
        }
        let intel = transport.type(of: "FS! ") == "ui16" && indices.allSatisfy {
            transport.type(of: "F\($0)Tg") == "fpe2"
        }
        if apple {
            for index in indices {
                do { try transport.write(modes[index]!, bytes: [0]) } catch { failed = true }
            }
            if transport.type(of: "Ftst") == "ui8 " {
                do { try transport.write("Ftst", bytes: [0]) } catch { failed = true }
                if transport.read("Ftst")?.number != 0 { failed = true }
            }
            for index in indices {
                if let value = transport.read(modes[index]!)?.number, value == 0 || value == 3 { continue }
                failed = true
            }
        } else if intel, let value = transport.read("FS! ")?.number, value.isFinite, (0...65535).contains(value) {
            let mask = indices.reduce(UInt16(value)) { $0 & ~(UInt16(1) << $1) }
            do { try transport.write("FS! ", bytes: [UInt8(mask >> 8), UInt8(mask & 255)]) }
            catch { failed = true }
            if transport.read("FS! ")?.number != Double(mask) { failed = true }
        } else { failed = true }
        if failed { throw HardwareReason.restoreFailed }
    }

    private func inventory() -> (fans: [FanReading], control: Control, modes: [Int: String]) {
        guard let transport, let count = transport.read("FNum")?.number,
              count.isFinite, count.rounded() == count, (1...8).contains(count) else { return ([], .unsupported, [:]) }
        var fans: [FanReading] = []
        var apple = true
        var modes: [Int: String] = [:]
        var intel = transport.read("FS! ")?.type == "ui16"
        let mask = transport.read("FS! ")?.number ?? 0
        for index in 0..<Int(count) {
            guard let rpm = transport.read("F\(index)Ac")?.number,
                  let minimum = transport.read("F\(index)Mn")?.number,
                  let maximum = transport.read("F\(index)Mx")?.number else { apple = false; intel = false; continue }
            let key = modeKey(index)
            let mode = key.flatMap { transport.read($0)?.number }
            if let key { modes[index] = key }
            let manual = mode == 1
                || transport.read("Ftst")?.number == 1
                || (mask.isFinite && (0...65535).contains(mask) && UInt16(mask) & (UInt16(1) << index) != 0)
            let fan = FanReading(id: index, rpm: rpm, minimum: minimum, maximum: maximum, manual: manual)
            guard fan.valid else { apple = false; intel = false; continue }
            fans.append(fan)
            apple = apple && key != nil && (mode == 0 || mode == 1 || mode == 3)
                && transport.read("F\(index)Tg")?.type == "flt "
            intel = intel && transport.read("F\(index)Tg")?.type == "fpe2" && maximum <= 16383.75
        }
        guard fans.count == Int(count) else { return (fans, .unsupported, modes) }
        return (fans, apple ? .appleSilicon : intel ? .intel : .unsupported, modes)
    }
    private func modeKey(_ index: Int) -> String? {
        ["F\(index)Md", "F\(index)md"].first { transport?.type(of: $0) == "ui8 " }
    }

}
