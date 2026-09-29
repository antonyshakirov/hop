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
    /// nil for what a run stopped early did not get to (Mbit/s, RPM).
    struct Result: Equatable {
        let down: Double?
        let up: Double?
        let rpm: Int?
    }

    private enum Outcome {
        case done(Result)
        case stopped(down: Double?, up: Double?)
        case failed
    }

    @Published private(set) var isRunning = false
    @Published private(set) var failed = false
    @Published private(set) var elapsed = 0
    @Published private(set) var liveDown: Double?
    @Published private(set) var liveUp: Double?
    @Published private(set) var last: Result?

    private var ticker: Timer?
    private var stopFlag: StopFlag?
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
        let down = defaults.object(forKey: Self.downKey) as? Double
        let up = defaults.object(forKey: Self.upKey) as? Double
        if down != nil || up != nil {
            last = Result(down: down, up: up, rpm: defaults.object(forKey: Self.rpmKey) as? Int)
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
        let flag = StopFlag()
        stopFlag = flag

        let onLive: @Sendable (Double?, Double?) -> Void = { [weak self] down, up in
            Task { @MainActor in
                if let down { self?.liveDown = down }
                if let up { self?.liveUp = up }
            }
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let outcome = SpeedTestController.measure(live: onLive, stop: flag)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.ticker?.invalidate()
                self.ticker = nil
                self.stopFlag = nil
                self.isRunning = false
                switch outcome {
                case .done(let result):
                    self.keep(result)
                case .stopped(let down, let up):
                    if let partial = SpeedSummary.stopped(down: down, up: up) {
                        self.keep(Result(down: partial.down, up: partial.up, rpm: nil))
                    }
                case .failed:
                    self.failed = true
                }
            }
        }
    }

    /// SPEC: docs/spec.md — "Speed test", stopping early: the run ends as if done.
    func stop() {
        stopFlag?.raise()
    }

    private func keep(_ result: Result) {
        last = result
        let defaults = UserDefaults.standard
        let values: [(String, Any?)] = [(Self.downKey, result.down), (Self.upKey, result.up), (Self.rpmKey, result.rpm)]
        for (key, value) in values {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        lastAt = Date()
        defaults.set(lastAt, forKey: Self.atKey)
        lastNetwork = Self.currentNetwork
        defaults.set(lastNetwork, forKey: Self.netKey)
    }

    /// Run through a pty: without a terminal the utility stays silent until the final SUMMARY.
    nonisolated private static func measure(
        live: @escaping @Sendable (Double?, Double?) -> Void, stop: StopFlag
    ) -> Outcome {
        var master: Int32 = 0
        var slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return .failed }
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
                stop.seen(down: down)
                live(down, nil)
            }
            if let up = SpeedSummary.lastNumber(in: chunk, after: "Uplink:"), up > 0 {
                stop.seen(up: up)
                live(nil, up)
            }
        }

        do {
            try process.run()
        } catch {
            masterHandle.readabilityHandler = nil
            return .failed
        }
        // CRITICAL: close OUR end of the slave right after launch — the child
        // has its own copy. Otherwise master never gets EOF, the final read
        // hangs forever, and the test keeps "running" minutes after the utility exits
        try? slaveHandle.close()

        // watchdog: networkQuality usually finishes within ~20s
        let deadline = Date().addingTimeInterval(90)
        while process.isRunning && Date() < deadline && !stop.raised {
            usleep(200_000)
        }
        if stop.raised {
            process.terminate()
            masterHandle.readabilityHandler = nil
            return .stopped(down: stop.down, up: stop.up)
        }
        if process.isRunning {
            process.terminate()
            masterHandle.readabilityHandler = nil
            return .failed
        }
        // collect the tail that may not have made it into readabilityHandler
        if let tail = String(data: masterHandle.availableData, encoding: .utf8), !tail.isEmpty {
            buffer.append(tail)
        }
        masterHandle.readabilityHandler = nil

        guard process.terminationStatus == 0,
              let summary = SpeedSummary.parse(buffer.value)
        else { return .failed }
        return .done(Result(down: summary.down, up: summary.up, rpm: summary.rpm))
    }
}

/// The stop button's signal, and the last live numbers a stopped run keeps.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isRaised = false
    private var lastDown: Double?
    private var lastUp: Double?

    func raise() { lock.withLock { isRaised = true } }
    var raised: Bool { lock.withLock { isRaised } }
    func seen(down: Double) { lock.withLock { lastDown = down } }
    func seen(up: Double) { lock.withLock { lastUp = up } }
    var down: Double? { lock.withLock { lastDown } }
    var up: Double? { lock.withLock { lastUp } }
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
