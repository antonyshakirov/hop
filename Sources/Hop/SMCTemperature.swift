import Foundation
import IOKit

/// Temperatures on an Intel Mac.
///
/// Apple Silicon publishes its sensors through IOHIDEventSystemClient
/// (`HIDTemperatureReader`); an Intel Mac publishes nothing there and keeps its
/// thermometers behind the SMC — the same chip every third-party monitor has
/// read for a decade. This is a READ-ONLY client for it: open `AppleSMC`, ask
/// for a key's type and size, read its bytes, decode.
///
/// Nothing here is fatal. A missing service, a refused connection or an unknown
/// key all end as `nil`, which the monitor already draws as "—", so the class is
/// safe to construct on any Mac including the ones that have no SMC keys worth
/// reading.
final class SMCTemperatureReader {
    // MARK: - The SMC's own structures (stable since 2008)

    private struct SMCVersion {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let kernelIndex: UInt32 = 2   // kSMCHandleYPCEvent
    private static let readKey: UInt8 = 5        // kSMCReadKey
    private static let getKeyInfo: UInt8 = 9     // kSMCGetKeyInfo

    private var connection: io_connect_t = 0

    /// Sensors worth showing, in the order they are tried. Intel Macs disagree
    /// about which of them exist — a MacBook has no `TG0D`, a Mac mini has no
    /// battery — so every key is optional and the first one that answers wins.
    private static let cpuKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "TCAD", "TCXC"]
    private static let gpuKeys = ["TG0P", "TG0D", "TG1P", "TG1D"]
    private static let ssdKeys = ["TH0P", "TH0a", "TH0b", "TH0x", "TM0P"]

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != kIOReturnSuccess {
            connection = 0
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    var isAvailable: Bool { connection != 0 }

    // MARK: - Reading

    /// The same shape `HIDTemperatureReader.read()` returns, so the two are
    /// interchangeable behind `TemperatureReader`.
    func read() -> (cpu: Double?, gpu: Double?, ssd: Double?) {
        (first(of: Self.cpuKeys), first(of: Self.gpuKeys), first(of: Self.ssdKeys))
    }

    /// Every key that answered, for the `--sensors` dump.
    func allSensors() -> [(name: String, value: Double)] {
        (Self.cpuKeys + Self.gpuKeys + Self.ssdKeys + ["TA0P", "TB0T", "Ts0P"])
            .compactMap { key in temperature(key).map { (key, $0) } }
    }

    private func first(of keys: [String]) -> Double? {
        for key in keys {
            if let value = temperature(key) { return value }
        }
        return nil
    }

    /// One key as °C, or nil when the key is absent or its value is nonsense.
    /// The plausibility window is the same one the HID reader uses: a sensor
    /// reading 0 or 200 is a sensor that is not really there.
    private func temperature(_ key: String) -> Double? {
        guard let (bytes, type, size) = readKey(key), size > 0 else { return nil }
        let value: Double?
        switch type {
        case fourCharCode("sp78"):
            // signed fixed point, 1/256 °C — the classic temperature type
            guard size >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            value = Double(raw) / 256.0
        case fourCharCode("flt "):
            guard size >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            value = Double(Float(bitPattern: raw))
        case fourCharCode("ui8 "), fourCharCode("ui16"):
            value = Double(bytes[0])
        default:
            value = nil
        }
        guard let value, value > 1, value < 130 else { return nil }
        return value
    }

    // MARK: - The two calls the SMC understands

    private func readKey(_ key: String) -> (bytes: [UInt8], type: UInt32, size: UInt32)? {
        guard connection != 0 else { return nil }
        var input = SMCParamStruct()
        input.key = fourCharCode(key)
        input.data8 = Self.getKeyInfo
        guard let info = call(input), info.result == 0 else { return nil }

        var read = SMCParamStruct()
        read.key = input.key
        read.keyInfo = info.keyInfo
        read.data8 = Self.readKey
        guard let out = call(read), out.result == 0 else { return nil }

        let size = min(info.keyInfo.dataSize, 32)
        var bytes = [UInt8](repeating: 0, count: Int(size))
        withUnsafeBytes(of: out.bytes) { raw in
            for i in 0..<Int(size) { bytes[i] = raw[i] }
        }
        return (bytes, info.keyInfo.dataType, size)
    }

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = withUnsafePointer(to: &input) { inPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(connection, Self.kernelIndex,
                                          inPtr, MemoryLayout<SMCParamStruct>.stride,
                                          outPtr, &outputSize)
            }
        }
        return result == kIOReturnSuccess ? output : nil
    }

    /// "TC0P" → the 32-bit key the SMC expects.
    private func fourCharCode(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

/// Whichever thermometer this Mac actually has.
///
/// Apple Silicon answers through the HID sensors and never opens the SMC path;
/// an Intel Mac has no HID sensors and answers through the SMC. Decided ONCE, by
/// asking — not by checking the architecture, so a Mac that reports through
/// neither simply reads nil instead of taking a branch that cannot work.
final class TemperatureReader {
    private let hid = HIDTemperatureReader()
    private lazy var smc: SMCTemperatureReader? = {
        let reader = SMCTemperatureReader()
        return reader.isAvailable ? reader : nil
    }()
    private var useSMC: Bool?

    func read() -> (cpu: Double?, gpu: Double?, ssd: Double?) {
        if useSMC != true {
            let values = hid.read()
            if values.cpu != nil || values.gpu != nil || values.ssd != nil {
                useSMC = false
                return values
            }
            useSMC = true   // nothing from HID: this is an Intel Mac (or a locked-down one)
        }
        return smc?.read() ?? (nil, nil, nil)
    }

    /// Both sources, labelled, for the `--sensors` dump: on an unfamiliar Mac the
    /// question is always WHICH thermometer answered.
    func allSensors() -> [(name: String, value: Double)] {
        let hidSensors = hid.allSensors().map { (name: "hid \($0.name)", value: $0.value) }
        let smcSensors = (smc?.allSensors() ?? []).map { (name: "smc \($0.name)", value: $0.value) }
        return hidSensors + smcSensors
    }
}
