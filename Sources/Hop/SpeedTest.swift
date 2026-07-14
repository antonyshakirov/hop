import CoreWLAN
import Darwin
import Foundation

/// Speed test via the macOS system utility `networkQuality` (Apple CDN).
/// The utility streams live numbers only to a terminal, so we attach it
/// to a pseudo-TTY and read Downlink/Uplink updates during the measurement.
@MainActor
final class SpeedTestController: ObservableObject {
    struct Result: Equatable {
        let down: Double // Mbit/s
        let up: Double
        let rpm: Int
    }

    @Published private(set) var isRunning = false
    @Published private(set) var failed = false
    @Published private(set) var elapsed = 0
    @Published private(set) var liveDown: Double?
    @Published private(set) var liveUp: Double?
    @Published private(set) var last: Result?

    private var ticker: Timer?
    private static let downKey = "speedLastDown"
    private static let upKey = "speedLastUp"
    private static let rpmKey = "speedLastRpm"
    private static let atKey = "speedLastAt"
    private static let netKey = "speedLastNet"

    init() {
        let defaults = UserDefaults.standard
        if let down = defaults.object(forKey: Self.downKey) as? Double,
           let up = defaults.object(forKey: Self.upKey) as? Double {
            last = Result(down: down, up: up, rpm: defaults.integer(forKey: Self.rpmKey))
            lastAt = defaults.object(forKey: Self.atKey) as? Date
            lastNetwork = defaults.string(forKey: Self.netKey)
        }
    }

    private(set) var lastAt: Date?
    private(set) var lastNetwork: String?

    /// The result is stale: more than 30 minutes passed or the Wi-Fi network changed
    /// (the SSID may be unavailable without Location permission — then time only).
    var isStale: Bool {
        guard last != nil else { return false }
        if let at = lastAt, Date().timeIntervalSince(at) > 30 * 60 { return true }
        if let saved = lastNetwork, let current = Self.currentNetwork,
           saved != current { return true }
        return false
    }

    nonisolated static var currentNetwork: String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    func run() {
        guard !isRunning else { return }
        isRunning = true
        failed = false
        elapsed = 0
        liveDown = nil
        liveUp = nil
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        let onLive: @Sendable (Double?, Double?) -> Void = { [weak self] down, up in
            Task { @MainActor in
                if let down { self?.liveDown = down }
                if let up { self?.liveUp = up }
            }
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = SpeedTestController.measure(live: onLive)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.ticker?.invalidate()
                self.ticker = nil
                self.isRunning = false
                if let result {
                    self.last = result
                    let defaults = UserDefaults.standard
                    defaults.set(result.down, forKey: Self.downKey)
                    defaults.set(result.up, forKey: Self.upKey)
                    defaults.set(result.rpm, forKey: Self.rpmKey)
                    self.lastAt = Date()
                    defaults.set(self.lastAt, forKey: Self.atKey)
                    self.lastNetwork = Self.currentNetwork
                    defaults.set(self.lastNetwork, forKey: Self.netKey)
                } else {
                    self.failed = true
                }
            }
        }
    }

    /// Run through a pty: without a terminal the utility stays silent until the final SUMMARY.
    nonisolated private static func measure(
        live: @escaping @Sendable (Double?, Double?) -> Void
    ) -> Result? {
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return nil }
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let buffer = TranscriptBuffer()
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            buffer.append(chunk)
            // live lines are redrawn via \r: take the latest values
            if let down = lastNumber(in: chunk, after: "Downlink:") { live(down, nil) }
            if let up = lastNumber(in: chunk, after: "Uplink:") { live(nil, up) }
        }

        do {
            try process.run()
        } catch {
            masterHandle.readabilityHandler = nil
            return nil
        }
        // CRITICAL: close OUR end of the slave right after launch — the child
        // has its own copy. Otherwise master never gets EOF, the final read
        // hangs forever, and the test keeps "running" minutes after the utility exits
        try? slaveHandle.close()

        // watchdog: networkQuality usually finishes within ~20s
        let deadline = Date().addingTimeInterval(90)
        while process.isRunning && Date() < deadline {
            usleep(200_000)
        }
        if process.isRunning {
            process.terminate()
            masterHandle.readabilityHandler = nil
            return nil
        }
        // collect the tail that may not have made it into readabilityHandler
        if let tail = String(data: masterHandle.availableData, encoding: .utf8), !tail.isEmpty {
            buffer.append(tail)
        }
        masterHandle.readabilityHandler = nil

        let text = buffer.value
        guard process.terminationStatus == 0,
              let down = lastNumber(in: text, after: "Downlink capacity:"),
              let up = lastNumber(in: text, after: "Uplink capacity:")
        else { return nil }
        var rpm = 0
        if let range = text.range(of: "Responsiveness:"),
           let match = text[range.upperBound...].range(
               of: #"(\d+) RPM"#, options: .regularExpression
           ) {
            rpm = Int(text[match].dropLast(4)) ?? 0
        }
        return Result(down: down, up: up, rpm: rpm)
    }

    /// Last number after the marker (lines are redrawn many times).
    nonisolated private static func lastNumber(in text: String, after marker: String) -> Double? {
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

/// Thread-safe accumulator for pty output.
final class TranscriptBuffer: @unchecked Sendable {
    private var storage = ""
    private let lock = NSLock()

    func append(_ chunk: String) {
        lock.lock()
        storage += chunk
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
