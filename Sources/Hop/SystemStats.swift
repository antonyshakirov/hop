import Darwin
import Foundation
import HopCore
import IOKit

/// Snapshot of system metrics. Any field can be nil — the sensor is unavailable,
/// the UI shows "—".
struct StatsSample {
    var cpuLoad: Double?      // 0...1
    var cpuTemp: Double?      // °C
    var gpuLoad: Double?      // 0...1
    var gpuTemp: Double?      // °C
    var memUsed: Double?      // bytes
    var memTotal: Double?     // bytes
    var swapUsed: Double?     // bytes (swap file)
    var memPressure: Int?     // macOS verdict: 1 normal, 2 warning, 4 critical
    var netDown: Double?      // bytes/s
    var netUp: Double?        // bytes/s
    var diskFree: Double?     // bytes
    var diskTotal: Double?    // bytes
    var ssdTemp: Double?      // °C, NAND sensor
    var battery: BatteryInfo?
    var uptime: TimeInterval?
}

struct BatteryInfo {
    var percent: Int?
    var tempC: Double?
    var cycles: Int?
    var healthPercent: Int?
    var isCharging: Bool
    var batteryWatts: Double? // + charging, − discharging
    var adapterWatts: Int?
}

/// System metrics. While the monitor tab is open — dense polling (2 s);
/// the rest of the time a light background tick (5 s) feeds the chart history
/// and the red-zone indicator — the monitor opens with past minutes already there.
@MainActor
final class SystemStatsController: ObservableObject {
    @Published private(set) var sample = StatsSample()
    /// Some metric is in the red zone (for the menu bar indicator).
    @Published private(set) var redZone = false

    init() {
        // sample right at startup: without it the first show of the monitor tab
        // rendered without the battery/uptime rows and "grew" from bottom to top
        refresh()
        startBackground()
    }

    /// History point: timestamp + value. Intervals are uneven
    /// (background 5 s, 2 s with the tab open) — the chart places points by time.
    struct HistoryPoint {
        let t: Date
        let v: Double
    }

    /// Chart history: accumulates in the background since app launch,
    /// buffer of ~61 minutes (the chart window is up to an hour).
    struct History {
        var cpuLoad: [HistoryPoint] = []
        var cpuTemp: [HistoryPoint] = []
        var memShare: [HistoryPoint] = []
        var netDown: [HistoryPoint] = []
        var netUp: [HistoryPoint] = []
    }
    @Published private(set) var history = History()

    /// Snapshot-only: pre-filled chart history for product screenshots —
    /// a live run has just two points by render time, which draws as empty.
    func injectDemoHistory(_ demo: History) {
        history = demo
    }

    private let cpu = CPUUsageReader()
    private let net = NetThroughputReader()
    private let sensors = HIDTemperatureReader()
    private var ticker: Timer?
    private var backgroundTicker: Timer?

    /// Background collector — always on, deliberately infrequent and cheap.
    private func startBackground() {
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.ticker == nil else { return } // tab is open — it does the ticking
                self.refresh()
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        backgroundTicker = t
    }

    func startPolling() {
        guard ticker == nil else { return }
        refresh() // primer for CPU/network deltas
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func stopPolling() {
        ticker?.invalidate()
        ticker = nil
    }

    func refresh() {
        var s = StatsSample()
        s.cpuLoad = cpu.read()
        s.gpuLoad = Self.gpuUsage()
        (s.memUsed, s.memTotal) = Self.memory()
        s.swapUsed = Self.swapUsed()
        s.memPressure = Self.memoryPressureLevel()
        (s.netDown, s.netUp) = net.read()
        (s.diskFree, s.diskTotal) = Self.disk()
        s.battery = Self.battery()
        s.uptime = Self.uptime()

        let temps = sensors.read()
        s.cpuTemp = temps.cpu
        s.gpuTemp = temps.gpu
        s.ssdTemp = temps.ssd
        sample = s

        Self.push(&history.cpuLoad, s.cpuLoad)
        Self.push(&history.cpuTemp, temps.cpu)
        if let used = s.memUsed, let total = s.memTotal, total > 0 {
            Self.push(&history.memShare, used / total)
        }
        Self.push(&history.netDown, s.netDown)
        Self.push(&history.netUp, s.netUp)

        redZone = Self.isRedZone(s)
    }

    private static func push(_ array: inout [HistoryPoint], _ value: Double?) {
        array.append(HistoryPoint(t: Date(), v: value ?? array.last?.v ?? 0))
        let cutoff = Date().addingTimeInterval(-61 * 60)
        if let keep = array.firstIndex(where: { $0.t >= cutoff }), keep > 0 {
            array.removeFirst(keep)
        }
    }

    /// Red zone — the same thresholds that color the values on the tab.
    private static func isRedZone(_ s: StatsSample) -> Bool {
        let d = UserDefaults.standard
        func value(_ key: String, _ def: Int) -> Double {
            Double((d.object(forKey: key) as? Int) ?? def)
        }
        let tempRed = value(Thresholds.tempRedKey, Thresholds.tempRedDefault)
        let loadRed = value(Thresholds.loadRedKey, Thresholds.loadRedDefault)
        let diskRed = value(Thresholds.diskRedKey, Thresholds.diskRedDefault)
        let battRed = value(Thresholds.battRedKey, Thresholds.battRedDefault)

        for temp in [s.cpuTemp, s.gpuTemp, s.ssdTemp, s.battery?.tempC] {
            if let temp, temp >= tempRed { return true }
        }
        if let load = s.cpuLoad, load * 100 >= loadRed { return true }
        if let free = s.diskFree, let total = s.diskTotal, total > 0,
           (1 - free / total) * 100 >= diskRed { return true }
        // battery: lower than the threshold is worse; don't alarm while charging
        if let percent = s.battery?.percent, let charging = s.battery?.isCharging,
           !charging, Double(percent) <= battRed { return true }
        return false
    }

    // MARK: - CPU / GPU / memory / network / disk

    private static func gpuUsage() -> Double? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any],
               let util = perf["Device Utilization %"] as? Int {
                return Double(util) / 100
            }
        }
        return nil
    }

    /// macOS's own memory verdict (kern.memorystatus_vm_pressure_level):
    /// 1 normal, 2 warning, 4 critical. The row color follows this signal —
    /// any formula over used/swap second-guesses the system and lies.
    private static func memoryPressureLevel() -> Int? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return nil }
        return Int(level)
    }

    /// Used swap: a real signal of memory pressure,
    /// unlike "used ÷ total" (macOS deliberately fills all RAM with cache).
    private static func swapUsed() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Double(usage.xsu_used)
    }

    private static func memory() -> (used: Double?, total: Double?) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (nil, nil) }

        let page = Double(vm_kernel_page_size)
        // like Activity Monitor: app memory (active) + wired + compressed
        let used = Double(stats.active_count &+ stats.wire_count &+ stats.compressor_page_count) * page

        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        return (used, total > 0 ? Double(total) : nil)
    }

    private static func disk() -> (free: Double?, total: Double?) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]) else { return (nil, nil) }
        let free = values.volumeAvailableCapacityForImportantUsage.map(Double.init)
        let total = values.volumeTotalCapacity.map(Double.init)
        return (free, total)
    }

    private static func uptime() -> TimeInterval? {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boottime, &size, nil, 0) == 0,
              boottime.tv_sec > 0 else { return nil }
        return Date().timeIntervalSince(
            Date(timeIntervalSince1970: Double(boottime.tv_sec))
        )
    }

    private static func battery() -> BatteryInfo? {
        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery")
        )
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }

        var info = BatteryInfo(isCharging: d["IsCharging"] as? Bool ?? false)

        if let cur = d["CurrentCapacity"] as? Int, let max = d["MaxCapacity"] as? Int, max > 0 {
            // on Apple Silicon CurrentCapacity is already a percentage (MaxCapacity == 100)
            info.percent = max == 100 ? cur : Int((Double(cur) / Double(max) * 100).rounded())
        }
        if let t = d["Temperature"] as? Double { info.tempC = t / 100 }
        info.cycles = d["CycleCount"] as? Int
        // NominalChargeCapacity is the calibrated figure System Settings
        // shows; AppleRawMaxCapacity is the instantaneous electrical estimate
        // that drifts with temperature/charge (95→97 on a new machine) and
        // read as a hop bug next to the system's 100%
        if let design = d["DesignCapacity"] as? Int, design > 0,
           let capacity = (d["NominalChargeCapacity"] as? Int) ?? (d["AppleRawMaxCapacity"] as? Int) {
            info.healthPercent = min(100, Int((Double(capacity) / Double(design) * 100).rounded()))
        }
        if let amperage = d["Amperage"] as? Int, let voltage = d["Voltage"] as? Int {
            // Sign/overflow correction lives in PowerMath (unit-tested): some
            // batteries report a discharge current as a 32-bit value widened into
            // 64 bits without sign extension, which the old 1<<64 no-op left as an
            // absurd positive wattage.
            info.batteryWatts = PowerMath.batteryWatts(amperage: amperage, voltage: voltage)
        }
        if let adapter = d["AdapterDetails"] as? [String: Any] {
            info.adapterWatts = adapter["Watts"] as? Int
        }
        return info
    }
}

// MARK: - CPU load (tick delta between polls)

final class CPUUsageReader {
    private var prev: [UInt32] = []

    func read() -> Double? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount
        ) == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let current = UnsafeBufferPointer(start: info, count: Int(infoCount))
            .map { UInt32(bitPattern: $0) }
        defer { prev = current }
        guard prev.count == current.count else { return nil }

        // ticks: user=0, system=1, idle=2, nice=3, stride 4
        var used: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * 4
            let user = UInt64(current[base] &- prev[base])
            let system = UInt64(current[base + 1] &- prev[base + 1])
            let idle = UInt64(current[base + 2] &- prev[base + 2])
            let nice = UInt64(current[base + 3] &- prev[base + 3])
            used += user + system + nice
            total += user + system + nice + idle
        }
        return total > 0 ? Double(used) / Double(total) : nil
    }
}

// MARK: - Network (byte sum across interfaces, delta between polls)

final class NetThroughputReader {
    private var prev: (down: UInt64, up: UInt64, at: Date)?

    func read() -> (down: Double?, up: Double?) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (nil, nil) }
        defer { freeifaddrs(addrs) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var p = addrs
        while let cur = p {
            let ifa = cur.pointee
            p = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            guard let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            down &+= UInt64(data.pointee.ifi_ibytes)
            up &+= UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { prev = (down, up, now) }
        guard let prev, down >= prev.down, up >= prev.up else { return (nil, nil) }
        let dt = now.timeIntervalSince(prev.at)
        guard dt > 0.1 else { return (nil, nil) }
        return (Double(down - prev.down) / dt, Double(up - prev.up) / dt)
    }
}

// MARK: - Temperatures via HID sensors (private API, degrades to nil)

/// Apple Silicon exposes temperatures via IOHIDEventSystemClient — a private API,
/// so we resolve the symbols via dlsym and silently turn off if Apple changes them.
final class HIDTemperatureReader {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private static let kEventTypeTemperature: Int64 = 15

    private let create: CreateFn?
    private let setMatching: SetMatchingFn?
    private let copyServices: CopyServicesFn?
    private let copyProperty: CopyPropertyFn?
    private let copyEvent: CopyEventFn?
    private let getFloat: GetFloatFn?
    private var client: AnyObject?

    init() {
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle = dlopen(nil, RTLD_NOW), let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        create = sym("IOHIDEventSystemClientCreate", CreateFn.self)
        setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self)
        copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self)
        copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self)
        copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self)
        getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self)

        if let create, let setMatching, let c = create(kCFAllocatorDefault)?.takeRetainedValue() {
            // 0xff00/5 — Apple vendor sensors (SoC temperature sensors)
            setMatching(c, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 5] as CFDictionary)
            client = c
        }
    }

    /// All temperature sensors with names — for diagnostics (`--sensors`).
    func allSensors() -> [(name: String, value: Double)] {
        guard let client, let copyServices, let copyProperty, let copyEvent, let getFloat,
              let services = copyServices(client)?.takeRetainedValue() as? [AnyObject]
        else { return [] }
        var out: [(String, Double)] = []
        for service in services {
            guard let name = copyProperty(service, "Product" as CFString)?
                .takeRetainedValue() as? String else { continue }
            guard let event = copyEvent(service, Self.kEventTypeTemperature, 0, 0)?
                .takeRetainedValue() else { continue }
            let value = getFloat(event, Int32(Self.kEventTypeTemperature << 16))
            out.append((name, value))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    func read() -> (cpu: Double?, gpu: Double?, ssd: Double?) {
        var cpuMax: Double?
        var gpuMax: Double?
        var ssdMax: Double?
        for (name, value) in allSensors() {
            guard value > 1, value < 130 else { continue }
            let n = name.lowercased()
            if n.contains("gpu") || n.contains("gfx") {
                gpuMax = max(gpuMax ?? 0, value)
            } else if n.contains("tdie") || n.contains("pacc") || n.contains("eacc")
                || n.contains("cpu") || n.contains("soc") {
                // PMU chips (tdie1..N) have no separate GPU sensor —
                // treat the tdie maximum as the SoC temperature and show it as cpu
                cpuMax = max(cpuMax ?? 0, value)
            } else if n.contains("nand") || n.contains("ssd") {
                ssdMax = max(ssdMax ?? 0, value)
            }
        }
        return (cpuMax, gpuMax, ssdMax)
    }
}

// MARK: - Formatting

enum StatsFormatting {
    static func percent(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }

    static func temp(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))°"
    }

    static func gb(_ bytes: Double?) -> String {
        guard let bytes else { return "—" }
        let gb = bytes / 1_073_741_824
        return gb >= 100 ? "\(Int(gb.rounded()))" : String(format: "%.1f", gb)
    }

    static func speed(_ bytesPerSec: Double?) -> String {
        guard let v = bytesPerSec else { return "—" }
        if v >= 1_048_576 { return String(format: "%.1f MB/s", v / 1_048_576) }
        if v >= 1024 { return String(format: "%.0f KB/s", v / 1024) }
        return "\(Int(v)) B/s"
    }

    static func watts(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.0fW", abs(v))
    }

    static func uptime(
        _ v: TimeInterval?, day: String = "d", hour: String = "h", minute: String = "m"
    ) -> String {
        guard let v, v > 0 else { return "—" }
        let minutes = Int(v) / 60
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return "\(days)\(day) \(hours)\(hour)" }
        if hours > 0 { return "\(hours)\(hour) \(minutes % 60)\(minute)" }
        return "\(minutes)\(minute)"
    }
}
