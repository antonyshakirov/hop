import Darwin
import Foundation

// SPEC: docs/spec.md — Cooling controls. SMC transport provenance is in SMC.swift.
public final class SMCFanHardware: @unchecked Sendable {
    private enum Control { case appleSilicon, intel, unsupported }
    private var transport: SMCTransport?
    private let modelIdentifier: String?
    private let connect: (() -> SMCTransport?)?
    private let clock: () -> Double
    private var nextConnectionAttempt: Double = 0
    private let canWrite: () -> Bool
    private let lock = NSLock()
    private var temperatureKeys: [String]?
    private var failure: FanFailure?
    public var lastFailure: FanFailure? { lock.lock(); defer { lock.unlock() }; return failure }

    public convenience init() {
        self.init(transport: nil, canWrite: { geteuid() == 0 }, modelIdentifier: FanDevice.modelIdentifier,
                  connect: { SMC() })
    }
    init(transport: SMCTransport?, canWrite: @escaping () -> Bool, modelIdentifier: String? = nil,
         connect: (() -> SMCTransport?)? = nil,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport; self.canWrite = canWrite; self.modelIdentifier = modelIdentifier
        self.connect = connect; self.clock = clock
    }

    private func connectIfNeeded() {
        guard transport == nil, let connect, clock() >= nextConnectionAttempt else { return }
        nextConnectionAttempt = clock() + 3
        transport = connect()
    }

    public func read() -> (fans: [FanReading], temperature: Double?, supportsControl: Bool, availability: FanAvailability) {
        lock.lock(); defer { lock.unlock() }
        connectIfNeeded()
        let inventory = inventory()
        let availability: FanAvailability = inventory.fans.isEmpty
            ? (FanDevice.isKnownFanless(modelIdentifier) ? .fanless : .unavailable)
            : (inventory.control == .unsupported ? .unsupported : .controllable)
        guard let transport else { return ([], nil, false, availability) }
        if temperatureKeys == nil {
            let keys = (0..<transport.keyCount()).compactMap { transport.key(at: $0) }
                .filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
            temperatureKeys = keys.isEmpty ? ["TC0P", "TC0D", "TC0E", "TC0F", "TCAD", "TCXC"] : keys
        }
        let temperatures = (temperatureKeys ?? []).compactMap { transport.read($0)?.number }
            .filter { $0.isFinite && (10...130).contains($0) }
        return (inventory.fans, temperatures.isEmpty ? nil
            : temperatures.reduce(0, +) / Double(temperatures.count), inventory.control != .unsupported, availability)
    }

    public func diagnosticKeys() -> [FanKeyReading] {
        lock.lock(); defer { lock.unlock() }
        connectIfNeeded()
        guard let transport else { return [] }
        return FanKeyReading.keys.map { key in
            let value = transport.read(key), error = transport.lastError
            return .init(key: key, type: value?.type ?? transport.type(of: key), number: value?.number,
                         readable: value != nil, error: error)
        }
    }

    public func setTargets(_ targets: [Int: Double]) throws {
        lock.lock(); defer { lock.unlock() }
        failure = nil
        guard canWrite() else { throw HardwareReason.unauthorized }
        connectIfNeeded()
        guard let transport else { throw HardwareReason.unavailable }
        let inventory = inventory()
        guard inventory.control != .unsupported,
              Set(targets.keys) == Set(inventory.fans.map(\.id)),
              inventory.fans.allSatisfy({ fan in
                  targets[fan.id].map { $0.isFinite && (fan.minimum...fan.maximum).contains($0) } == true
              }) else { throw HardwareReason.unsupported }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        switch inventory.control {
        case .appleSilicon: try takeManualControl(inventory.modes, deadline: deadline)
        case .intel:
            guard let value = transport.read("FS! ")?.number,
                  value.isFinite, (0...65535).contains(value) else { throw HardwareReason.commandFailed }
            let mask = inventory.fans.reduce(UInt16(value)) { $0 | (UInt16(1) << $1.id) }
            try write("FS! ", bytes: [UInt8(mask >> 8), UInt8(mask & 255)], phase: .takeover, expected: Double(mask))
            try confirm("FS! ", expected: Double(mask), phase: .takeover, deadline: deadline)
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
            try write("F\(fan.id)Tg", bytes: bytes, phase: .targetWrite, expected: rpm)
            try confirm("F\(fan.id)Tg", expected: rpm, phase: .targetReadback, deadline: deadline, tolerance: 1)
        }
        // SPEC: every potentially waiting target poll precedes the final ownership proof.
        for fan in inventory.fans {
            try confirm("F\(fan.id)Tg", expected: targets[fan.id]!, phase: .targetReadback, deadline: deadline, tolerance: 1)
        }
        if inventory.control == .appleSilicon {
            for key in inventory.modes.values.sorted() {
                let actual = transport.read(key)?.number
                guard actual == 1 else {
                    failure = .init(phase: .modeReadback, key: key, expected: 1, actual: actual)
                    throw HardwareReason.commandFailed
                }
            }
        } else {
            let value = transport.read("FS! ")?.number
            guard let value, value.isFinite, (0...65535).contains(value),
                  inventory.fans.allSatisfy({ UInt16(value) & (UInt16(1) << $0.id) != 0 }) else {
                failure = .init(phase: .modeReadback, key: "FS! ", actual: value)
                throw HardwareReason.commandFailed
            }
        }
        failure = nil
    }

    private func takeManualControl(_ modes: [Int: String], deadline: Double) throws {
        guard let transport else { throw HardwareReason.unavailable }
        var lastWrite: FanFailure?
        while true {
            let pending = modes.values.sorted().filter { transport.read($0)?.number != 1 }
            if pending.isEmpty { return }
            // SPEC: Ftst unlocks a transition; firmware need not keep it set once modes are manual.
            if transport.type(of: "Ftst") == "ui8 ", transport.read("Ftst")?.number != 1 {
                do { try write("Ftst", bytes: [1], phase: .takeover, expected: 1) }
                catch { lastWrite = failure }
            }
            for key in pending {
                do { try write(key, bytes: [1], phase: .takeover, expected: 1) }
                catch { lastWrite = failure }
            }
            if modes.values.allSatisfy({ transport.read($0)?.number == 1 }) { return }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                let key = modes.values.sorted().first { transport.read($0)?.number != 1 }
                failure = lastWrite ?? .init(phase: .takeover, key: key, expected: 1,
                                            actual: key.flatMap { transport.read($0)?.number })
                throw HardwareReason.commandFailed
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func write(_ key: String, bytes: [UInt8], phase: FanFailure.Phase, expected: Double) throws {
        do { try transport?.write(key, bytes: bytes) }
        catch {
            failure = .init(phase: phase, key: key, expected: expected,
                            actual: transport?.read(key)?.number, error: error)
            throw error
        }
    }

    private func confirm(_ key: String, expected: Double, phase: FanFailure.Phase,
                         deadline: Double, tolerance: Double = 0) throws {
        while true {
            let actual = transport?.read(key)?.number
            if let actual, actual.isFinite, abs(actual - expected) <= tolerance { return }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                failure = .init(phase: phase, key: key, expected: expected, actual: actual)
                throw HardwareReason.commandFailed
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    public func restore(indices: [Int]) throws {
        lock.lock(); defer { lock.unlock() }
        failure = nil
        guard !indices.isEmpty else { return }
        guard canWrite(), indices.count <= 8, Set(indices).count == indices.count,
              indices.allSatisfy({ (0..<8).contains($0) }) else { throw HardwareReason.unauthorized }
        connectIfNeeded()
        guard let transport else { failure = .init(phase: .release); throw HardwareReason.unavailable }
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
            for key in modes.values.sorted() where !automatic(transport.read(key)?.number) {
                do { try write(key, bytes: [0], phase: .release, expected: 0) } catch {}
            }
            let test = transport.type(of: "Ftst") == "ui8 "
            if test, transport.read("Ftst")?.number != 0 {
                do { try write("Ftst", bytes: [0], phase: .release, expected: 0) } catch {}
            }
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while true {
                let key = modes.values.sorted().first { !automatic(transport.read($0)?.number) }
                    ?? (test && transport.read("Ftst")?.number != 0 ? "Ftst" : nil)
                if let key {
                    guard ProcessInfo.processInfo.systemUptime < deadline else {
                        failure = failure ?? .init(phase: .release, key: key, expected: 0,
                                                   actual: transport.read(key)?.number)
                        throw HardwareReason.restoreFailed
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                } else { failure = nil; return }
            }
        } else if intel, let value = transport.read("FS! ")?.number, value.isFinite, (0...65535).contains(value) {
            let mask = indices.reduce(UInt16(value)) { $0 & ~(UInt16(1) << $1) }
            if UInt16(value) != mask {
                do { try write("FS! ", bytes: [UInt8(mask >> 8), UInt8(mask & 255)], phase: .release, expected: Double(mask)) }
                catch { throw HardwareReason.restoreFailed }
            }
            do { try confirm("FS! ", expected: Double(mask), phase: .release,
                             deadline: ProcessInfo.processInfo.systemUptime + 3) }
            catch { throw HardwareReason.restoreFailed }
        } else { failure = .init(phase: .release); throw HardwareReason.restoreFailed }
        failure = nil
    }

    private func automatic(_ mode: Double?) -> Bool { mode == 0 || mode == 3 }

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
