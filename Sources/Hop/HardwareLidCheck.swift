import Foundation
import HopHardwareKit

// SPEC: docs/spec.md — Lid response and latest intent, installed Dev verification.
@MainActor
enum HardwareLidCheck {
    private struct Sample: Encodable {
        let target: Bool
        let seconds: Double
    }
    private struct Result: Encodable {
        let samples: [Sample]
        let rapidOnOff: Bool
        let rapidOnOffOn: Bool
        let offStableSeconds: Double
        let finalSleepDisabled: Bool
    }

    static func run(service: SystemCoolingService) async throws -> Data {
        guard service.state == .enabled else { throw HardwareReason.serviceApproval }
        let backend = SystemHardwareBackend()
        guard backend.observe().lidClosed == false, try !backend.sleepDisabled() else { throw HardwareReason.busy }
        let status = try await service.request(.init(.status))
        guard !status.active, !status.restorationPending, !status.maintenance,
              status.reason == nil || status.reason == .stopped else { throw HardwareReason.busy }
        let controller = CoolingController(service: service)
        var samples: [Sample] = []
        do {
            for target in [true, false, true, false, true, false] {
                guard backend.observe().lidClosed == false else { throw HardwareReason.busy }
                let start = ProcessInfo.processInfo.systemUptime
                try await controller.setLid(target, until: nil)
                guard try backend.sleepDisabled() == target, controller.snapshot.lid == target else {
                    throw HardwareReason.commandFailed
                }
                samples.append(.init(target: target, seconds: ProcessInfo.processInfo.systemUptime - start))
            }
            try await rapid([true, false], controller: controller, backend: backend)
            try await rapid([true, false, true], controller: controller, backend: backend)
            try await controller.setLid(false, until: nil)
            let start = ProcessInfo.processInfo.systemUptime
            while ProcessInfo.processInfo.systemUptime - start < 12 {
                guard try !backend.sleepDisabled() else { throw HardwareReason.commandFailed }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            let final = try await service.request(.init(.status))
            guard !final.active, !final.lid, !final.restorationPending else { throw HardwareReason.restoreFailed }
            service.invalidate()
            return try JSONEncoder().encode(Result(samples: samples, rapidOnOff: true, rapidOnOffOn: true,
                offStableSeconds: ProcessInfo.processInfo.systemUptime - start, finalSleepDisabled: false))
        } catch {
            _ = try? await service.request(.init(.stop))
            service.invalidate()
            throw error
        }
    }

    private static func rapid(_ targets: [Bool], controller: CoolingController,
                              backend: SystemHardwareBackend) async throws {
        guard backend.observe().lidClosed == false else { throw HardwareReason.busy }
        var started = 0
        var tasks: [Task<Void, Error>] = []
        for target in targets {
            tasks.append(Task { @MainActor in
                started += 1
                do { try await controller.setLid(target, until: nil) }
                catch HardwareReason.stopped { return }
            })
            while started < tasks.count { await Task.yield() }
        }
        var failure: Error?
        for task in tasks {
            do { try await task.value } catch { failure = error }
        }
        if let failure { throw failure }
        guard let last = targets.last, try backend.sleepDisabled() == last,
              controller.snapshot.lid == last else { throw HardwareReason.commandFailed }
    }
}
