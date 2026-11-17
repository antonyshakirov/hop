import Foundation
import Darwin

public struct HardwareMaintenance: Codable, Equatable {
    public let transaction: UUID
    public let application: String
    public let user: UInt32
    public init(transaction: UUID, application: String, user: UInt32) {
        self.transaction = transaction; self.application = application; self.user = user
    }
}

public struct HardwareRecovery: Codable, Equatable {
    public var sleepDisabledBefore: Bool?
    public var fans: [Int]
    public var lidOverrideApplied: Bool
    public var sleepOverrideRestored: Bool
    public var maintenance: HardwareMaintenance?
    public var idleLidRelease = false
    public init(sleepDisabledBefore: Bool? = nil, fans: [Int] = [], maintenance: HardwareMaintenance? = nil,
                lidOverrideApplied: Bool = false, sleepOverrideRestored: Bool = false) {
        self.sleepDisabledBefore = sleepDisabledBefore; self.fans = fans
        self.maintenance = maintenance; self.lidOverrideApplied = lidOverrideApplied
        self.sleepOverrideRestored = sleepOverrideRestored
    }
    private enum CodingKeys: String, CodingKey { case sleepDisabledBefore, fans, maintenance, lidOverrideApplied, sleepOverrideRestored, idleLidRelease }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sleepDisabledBefore = try values.decodeIfPresent(Bool.self, forKey: .sleepDisabledBefore)
        fans = try values.decode([Int].self, forKey: .fans)
        maintenance = try values.decodeIfPresent(HardwareMaintenance.self, forKey: .maintenance)
        lidOverrideApplied = try values.decodeIfPresent(Bool.self, forKey: .lidOverrideApplied) ?? false
        sleepOverrideRestored = try values.decodeIfPresent(Bool.self, forKey: .sleepOverrideRestored) ?? false
        idleLidRelease = try values.decodeIfPresent(Bool.self, forKey: .idleLidRelease) ?? false
    }
    public var hasOverrides: Bool { sleepDisabledBefore != nil || !fans.isEmpty }
    public var empty: Bool { !hasOverrides && maintenance == nil }
    public var valid: Bool {
        (!idleLidRelease || lidOverrideApplied)
            && (!lidOverrideApplied || sleepDisabledBefore == false)
            && (!sleepOverrideRestored || lidOverrideApplied)
            && fans.count <= 8 && Set(fans).count == fans.count && fans.allSatisfy { (0..<8).contains($0) }
            && (maintenance.map { HardwareIdentity.applications.contains($0.application) && $0.user != 0 } ?? true)
    }
}

public protocol HardwareJournal: AnyObject {
    func acquire() throws
    func load() throws -> HardwareRecovery?
    func save(_ record: HardwareRecovery) throws
    func clear() throws
    func release()
}

public protocol HardwareBackend: AnyObject {
    var fanDiagnostic: FanFailure? { get }
    func observe() -> HardwareObservation
    func sleepDisabled() throws -> Bool
    func setSleepDisabled(_ disabled: Bool) throws
    func restoreClosedLidBehavior() throws
    func idleLidReleaseReady() -> Bool
    func setFans(_ targets: [Int: Double]) throws
    func restoreFans(_ indices: [Int]) throws
}

public extension HardwareBackend {
    var fanDiagnostic: FanFailure? { nil }
    func idleLidReleaseReady() -> Bool { false }
}

/// Serializes hardware ownership, independent cutoffs and durable recovery.
public final class HardwareCoordinator {
    private let backend: HardwareBackend
    private let journal: HardwareJournal
    private let now: () -> Double
    private let application: String
    private var recovery = HardwareRecovery()
    private var locked = false
    private var unreadableRecovery = false
    private var owner: UUID?
    private var configuration: HardwareConfiguration?
    private var appliedFanTargets: [Int: Double]?
    private var lastHeartbeat: Double = 0
    private var deadline: Double?
    private var reason: HardwareReason?
    private var maintenance: HardwareMaintenance?

    private var stopCause: HardwareReason?
    private var fanFailure: FanFailure?
    private var fanRecoveryFailure: FanFailure?

    public init(backend: HardwareBackend, journal: HardwareJournal,
                application: String = "com.antonshakirov.minimo",
                now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.backend = backend; self.journal = journal; self.now = now
        self.application = application
    }

    public func recoverAtLaunch() {
        do {
            try acquire()
            try restore(reason: .disconnected)
        } catch { reason = error as? HardwareReason ?? .restoreFailed }
    }

    public func tick() {
        if configuration == nil {
            if !locked && (reason == .busy || maintenance != nil) { recoverAtLaunch() }
            if locked && (!recovery.empty || unreadableRecovery) {
                do { try restore(reason: stopCause ?? reason ?? .restoreFailed) }
                catch { reason = .restoreFailed }
            }
            return
        }
        guard let configuration else { return }
        let time = now(), observation = backend.observe()
        if let deadline, time >= deadline { stop(.expired); return }
        if time - lastHeartbeat >= 90 || time < lastHeartbeat { stop(.heartbeat); return }
        if let cutoff = cutoff(configuration, observation) { stop(cutoff); return }
        if configuration.lid, observation.lidClosed == true, backend.idleLidReleaseReady() {
            releaseIdleLid()
            return
        }
        if configuration.fan.mode != .automatic {
            do {
                let speeds = try fanSpeeds(configuration.fan, observation)
                try backend.setFans(speeds)
                appliedFanTargets = speeds
            } catch {
                if fanFailure == nil { fanFailure = backend.fanDiagnostic }
                stop(error as? HardwareReason ?? .commandFailed)
            }
        }
    }

    private func releaseIdleLid() {
        guard var desired = configuration, desired.lid else { return }
        do {
            recovery.idleLidRelease = true
            try journal.save(recovery)
            try restoreSleep(requestSleep: false)
            var next = recovery
            next.sleepDisabledBefore = nil
            next.lidOverrideApplied = false
            next.sleepOverrideRestored = false
            next.idleLidRelease = false
            desired.lid = false
            desired.duration = nil
            deadline = nil
            if desired.needsLease {
                try journal.save(next)
                recovery = next
                configuration = desired
            } else {
                try journal.clear()
                recovery = .init()
                configuration = nil; appliedFanTargets = nil; owner = nil; deadline = nil
                reason = .stopped
                journal.release(); locked = false
            }
        } catch {
            configuration = nil; appliedFanTargets = nil; owner = nil; deadline = nil
            reason = .restoreFailed
        }
    }

    public func disconnect(owner: UUID) {
        if self.owner == owner { stop(.disconnected) }
    }

    public func shutdown() { stop(.disconnected) }

    public func handle(_ request: HardwareRequest, owner: UUID, user: UInt32 = UInt32(getuid())) -> HardwareStatus {
        guard request.supportedVersion else { return status(error: .protocolMismatch) }
        if let active = self.owner, active != owner {
            var value = status(error: .busy)
            value.active = false; value.lid = false; value.policy = .init()
            return value
        }
        if request.operation == .status {
            var value = status()
            if let marker = maintenance, marker.application == application, marker.user == user {
                value.maintenanceID = marker.transaction
            }
            return value
        }
        switch request.operation {
        case .status: break
        case .prepareUpdate, .finishUpdate:
            guard configuration == nil, let transaction = request.transaction else { return status(error: .busy) }
            do {
                try acquire()
                guard !recovery.hasOverrides, !unreadableRecovery else { throw HardwareReason.restoreFailed }
                let expected = HardwareMaintenance(transaction: transaction, application: application, user: user)
                if request.operation == .prepareUpdate {
                    guard recovery.maintenance == nil || recovery.maintenance == expected else { throw HardwareReason.busy }
                    recovery.maintenance = expected
                    try journal.save(recovery)
                    maintenance = expected
                } else {
                    guard recovery.maintenance == nil || recovery.maintenance == expected else { throw HardwareReason.unauthorized }
                    try journal.clear()
                    recovery = .init(); maintenance = nil
                }
                journal.release(); locked = false
                reason = maintenance == nil ? .stopped : .busy
                return status(error: .stopped)
            } catch {
                if locked && !recovery.hasOverrides && !unreadableRecovery { journal.release(); locked = false }
                return status(error: error as? HardwareReason ?? .commandFailed)
            }
        case .stop: stop(.stopped)
        case .renew:
            if self.owner == owner, configuration != nil { lastHeartbeat = now() }
        case .configure:
            guard let desired = request.configuration, desired.valid else { return status(error: .invalid) }
            if !desired.needsLease {
                stop(.stopped)
                if !locked { clearFanFailure() }
                return status()
            }
            do { try configure(desired, owner: owner) }
            catch {
                let failure = error as? HardwareReason ?? .commandFailed
                if locked { stop(failure) }
                else { reason = failure }
            }
        }
        return status()
    }

    private func acquire() throws {
        guard !locked else { return }
        try journal.acquire()
        locked = true
        do {
            recovery = try journal.load() ?? HardwareRecovery()
            guard recovery.valid else { throw HardwareReason.invalid }
            unreadableRecovery = false
            maintenance = recovery.maintenance
        } catch {
            unreadableRecovery = true
            throw HardwareReason.restoreFailed
        }
    }

    private func configure(_ desired: HardwareConfiguration, owner: UUID) throws {
        let reading = backend.observe()
        if let cutoff = cutoff(desired, reading) { throw cutoff }
        let speeds = try fanSpeeds(desired.fan, reading)
        try acquire()
        guard recovery.maintenance == nil else { throw HardwareReason.busy }
        if self.owner == nil, !recovery.empty {
            let restoringLid = recovery.sleepDisabledBefore != nil
            try restore(reason: .disconnected)
            // SPEC: queued recovery sleep cannot acknowledge a new active session in the same request.
            guard !restoringLid else { throw HardwareReason.busy }
            try acquire()
        }
        guard !unreadableRecovery else { throw HardwareReason.restoreFailed }
        var next = recovery
        let sleepAlreadyDisabled = desired.lid ? try backend.sleepDisabled() : false
        if desired.lid, next.sleepDisabledBefore == nil {
            guard !sleepAlreadyDisabled else { throw HardwareReason.busy }
            next.sleepDisabledBefore = false
        }
        if desired.fan.mode != .automatic, next.fans.isEmpty {
            guard !reading.fans.contains(where: \.manual) else { throw HardwareReason.busy }
            next.fans = reading.fans.map(\.id)
        }
        try journal.save(next)
        recovery = next
        if desired.lid {
            if !sleepAlreadyDisabled {
                try backend.setSleepDisabled(true)
                guard try backend.sleepDisabled() else { throw HardwareReason.commandFailed }
            }
            next.lidOverrideApplied = true
            next.sleepOverrideRestored = false
            try journal.save(next)
            recovery = next
        }
        let keepCurrentFans = configuration?.fan == desired.fan && appliedFanTargets == speeds && !recovery.fans.isEmpty
            && Set(reading.fans.map(\.id)) == Set(recovery.fans) && reading.fans.allSatisfy(\.manual)
        if desired.fan.mode != .automatic, !keepCurrentFans {
            do { try backend.setFans(speeds); appliedFanTargets = speeds }
            catch {
                if fanFailure == nil { fanFailure = backend.fanDiagnostic }
                throw error
            }
        } else if desired.fan.mode == .automatic, !recovery.fans.isEmpty {
            try backend.restoreFans(recovery.fans)
            appliedFanTargets = nil
            next.fans = []
        }
        if !desired.lid, recovery.sleepDisabledBefore != nil {
            try restoreSleep()
            next = recovery
            next.sleepDisabledBefore = nil
            next.lidOverrideApplied = false
            next.sleepOverrideRestored = false
            next.idleLidRelease = false
            try journal.save(next)
            recovery = next
        }
        try journal.save(next)
        recovery = next
        self.owner = owner
        configuration = desired
        lastHeartbeat = now()
        deadline = desired.duration.map { lastHeartbeat + $0 }
        reason = nil
        clearFanFailure()
    }

    private func fanSpeeds(_ policy: FanPolicy, _ reading: HardwareObservation) throws -> [Int: Double] {
        guard policy.mode != .automatic else { return [:] }
        guard reading.supportsControl else { throw HardwareReason.unsupported }
        if reading.thermalSeverity == 2 {
            return try FanPolicy(mode: .maximum).speeds(for: reading.fans, temperature: nil)
        }
        return try policy.speeds(for: reading.fans, temperature: reading.freshTemperature)
    }

    private func cutoff(_ desired: HardwareConfiguration, _ reading: HardwareObservation) -> HardwareReason? {
        if reading.thermalSeverity >= (desired.lid ? 2 : 3) { return .thermal }
        if desired.lid {
            guard reading.lidClosed != nil, let battery = reading.onBattery else { return .sensor }
            if battery {
                guard let charge = reading.batteryPercent, (0...100).contains(charge) else { return .sensor }
                if charge <= 10 { return .battery }
            }
        }
        return nil
    }

    private func clearFanFailure() { stopCause = nil; fanFailure = nil; fanRecoveryFailure = nil }

    private func stop(_ reason: HardwareReason) {
        if reason != .stopped, stopCause == nil { stopCause = reason }
        configuration = nil; appliedFanTargets = nil; owner = nil; deadline = nil
        do { try restore(reason: reason) }
        catch { self.reason = .restoreFailed }
    }

    private func restore(reason: HardwareReason) throws {
        self.reason = reason
        guard locked else { return }
        guard !unreadableRecovery else { throw HardwareReason.restoreFailed }
        var failed = false
        if !recovery.fans.isEmpty {
            do { try backend.restoreFans(recovery.fans); appliedFanTargets = nil; fanRecoveryFailure = nil }
            catch { failed = true; fanRecoveryFailure = backend.fanDiagnostic }
        }
        try restoreSleep(requestSleep: !failed)
        guard !failed else { throw HardwareReason.restoreFailed }
        if let marker = recovery.maintenance {
            if recovery.hasOverrides { try journal.save(HardwareRecovery(maintenance: marker)) }
            recovery = HardwareRecovery(maintenance: marker)
            maintenance = marker
            self.reason = .busy
        } else {
            try journal.clear()
            recovery = HardwareRecovery()
            maintenance = nil
        }
        journal.release(); locked = false
    }

    private func restoreSleep(requestSleep: Bool = true) throws {
        guard let original = recovery.sleepDisabledBefore else { return }
        // SPEC: every retry must persist idle intent before changing sleep state.
        if recovery.idleLidRelease { try journal.save(recovery) }
        if !recovery.sleepOverrideRestored {
            if !original, !recovery.lidOverrideApplied, try backend.sleepDisabled() {
                // SPEC: retain confirmed ownership even when a journal failure requires best-effort reset.
                recovery.lidOverrideApplied = true
                do { try journal.save(recovery) } catch { /* SPEC: reset must still be attempted. */ }
            }
            try backend.setSleepDisabled(original)
            guard try backend.sleepDisabled() == original else { throw HardwareReason.restoreFailed }
            if recovery.lidOverrideApplied { recovery.sleepOverrideRestored = true }
        }
        if recovery.lidOverrideApplied {
            var saved = true
            do { try journal.save(recovery) } catch { saved = false }
            if requestSleep && !recovery.idleLidRelease {
                // SPEC: a later foreign override is not ours to reset or bypass during retry.
                guard try !backend.sleepDisabled() else { throw HardwareReason.restoreFailed }
                try backend.restoreClosedLidBehavior()
            }
            guard saved else { throw HardwareReason.restoreFailed }
        }
    }

    private func status(error: HardwareReason? = nil) -> HardwareStatus {
        let reading = backend.observe()
        var status = HardwareStatus()
        status.fans = reading.fans.filter(\.valid)
        status.temperature = reading.freshTemperature.flatMap { $0.isFinite ? $0 : nil }
        status.supportsControl = reading.supportsControl
        status.fanAvailability = reading.fanAvailability
        status.active = configuration != nil

        status.policy = configuration?.fan ?? .init()
        status.restorationPending = locked && (recovery.hasOverrides || unreadableRecovery) && configuration == nil
        status.lid = configuration?.lid ?? (status.restorationPending && recovery.sleepDisabledBefore != nil)
        status.maintenance = maintenance != nil
        status.reason = error ?? reason
        status.stopCause = stopCause
        status.fanFailure = fanFailure
        status.fanRecoveryFailure = fanRecoveryFailure
        return status
    }
}
