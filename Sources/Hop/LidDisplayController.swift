import Foundation
import CoreGraphics
import IOKit.pwr_mgt
import OSLog

// SPEC: docs/spec.md — "Closed-lid display sleep".
@MainActor
final class LidDisplayController {
    struct Environment {
        var lidClosed: () -> Bool?
        var externalDisplayConnected: () -> Bool?
        var sleepDisplays: () -> Bool
        var wakeDisplays: () -> Bool
        var dimBuiltin: () -> Void
        var restoreBuiltin: () -> Void
    }

    private enum Mode {
        case awake, dimmed, asleep, sleepFallback
    }

    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "LidDisplay")
    private static var wakeAssertion: IOPMAssertionID = 0
    private let environment: Environment
    private var poll: Timer?
    private var mode = Mode.awake

    init(environment: Environment) {
        self.environment = environment
    }

    convenience init() {
        let dimmer = LidDimmer()
        self.init(environment: Environment(
            lidClosed: { LidDimmer.clamshellClosed() },
            externalDisplayConnected: { Self.externalDisplayConnected() },
            sleepDisplays: { Self.sleepDisplays() },
            wakeDisplays: { Self.wakeDisplays() },
            dimBuiltin: { dimmer.start() },
            restoreBuiltin: { dimmer.stop() }
        ))
    }

    func start() {
        guard poll == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
        refresh()
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        if mode == .dimmed || mode == .sleepFallback {
            environment.restoreBuiltin()
        } else if mode == .asleep, environment.lidClosed() == false {
            guard environment.wakeDisplays() else { return }
        }
        mode = .awake
    }

    func refresh() {
        guard poll != nil, let closed = environment.lidClosed() else { return }
        if !closed {
            if mode == .asleep {
                guard environment.wakeDisplays() else { return }
            } else if mode == .dimmed || mode == .sleepFallback {
                environment.restoreBuiltin()
            }
            mode = .awake
            return
        }
        guard let external = environment.externalDisplayConnected() else { return }
        if external {
            if mode == .asleep {
                guard environment.wakeDisplays() else { return }
            }
            if mode != .dimmed && mode != .sleepFallback {
                environment.dimBuiltin()
            }
            mode = .dimmed
        } else {
            sleepBuiltin()
        }
    }

    private func sleepBuiltin() {
        guard mode != .asleep, mode != .sleepFallback else { return }
        if mode == .dimmed { environment.restoreBuiltin() }
        if environment.sleepDisplays() {
            mode = .asleep
        } else {
            environment.dimBuiltin()
            mode = .sleepFallback
        }
    }

    private static func externalDisplayConnected() -> Bool? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }

    private static func sleepDisplays() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                log.error("Display sleep request failed: \(process.terminationStatus)")
                return false
            }
            return true
        } catch {
            log.error("Display sleep request failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func wakeDisplays() -> Bool {
        let result = IOPMAssertionDeclareUserActivity(
            "Hop — lid display wake" as CFString, kIOPMUserActiveLocal, &wakeAssertion
        )
        if result != kIOReturnSuccess {
            log.error("Display wake request failed: \(result)")
        }
        return result == kIOReturnSuccess
    }
}
