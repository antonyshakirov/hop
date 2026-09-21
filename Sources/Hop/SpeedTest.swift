import CoreWLAN
import Darwin
import Foundation
import HopCore

/// Speed test via the macOS system utility `networkQuality` (Apple CDN).
/// The utility streams live numbers only to a terminal, so we attach it
/// to a pseudo-TTY and read Downlink/Uplink updates during the measurement.
/// SPEC: docs/spec.md — "Speed test", why the directions are measured apart.
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

    /// SPEC: docs/spec.md — "Onboarding", the module preview.
    init(demo: Bool) {
        last = Result(down: 834, up: 112, rpm: 1450)
        lastAt = Date()
        lastNetwork = Self.currentNetwork
    }

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
        process.arguments = ["-s"]
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        let buffer = TranscriptBuffer()
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            buffer.append(chunk)
            // live lines are redrawn via \r: take the latest values
            // A direction that has not started yet reads 0.000 for as long as the
            // other one runs; the row keeps its placeholder instead of showing it.
            if let down = SpeedSummary.lastNumber(in: chunk, after: "Downlink:"), down > 0 {
                live(down, nil)
            }
            if let up = SpeedSummary.lastNumber(in: chunk, after: "Uplink:"), up > 0 {
                live(nil, up)
            }
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

        guard process.terminationStatus == 0,
              let summary = SpeedSummary.parse(buffer.value)
        else { return nil }
        return Result(down: summary.down, up: summary.up, rpm: summary.rpm)
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
