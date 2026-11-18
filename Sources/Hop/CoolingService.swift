import AppKit
import Foundation
import HopHardwareKit
import ServiceManagement

enum CoolingServiceState { case enabled, approval, missing, unavailable }

@MainActor
protocol CoolingService: AnyObject {
    /// The last known state; never blocks.
    var state: CoolingServiceState { get }
    /// False until the first read has finished.
    var stateKnown: Bool { get }
    /// Reads the system's current state off the main thread and refreshes `state`.
    func readState() async -> CoolingServiceState
    func register() async throws
    func unregister() async throws
    func request(_ request: HardwareRequest) async throws -> HardwareStatus
    func localStatus() async -> HardwareStatus
    func localDiagnostics() async -> [FanKeyReading]
    func invalidate()
}

extension CoolingService {
    var stateKnown: Bool { true }
    func readState() async -> CoolingServiceState { state }
    func localDiagnostics() async -> [FanKeyReading] { [] }
}

private final class HardwareReply {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HardwareStatus, Error>?
    init(_ continuation: CheckedContinuation<HardwareStatus, Error>) { self.continuation = continuation }
    @discardableResult
    func finish(_ result: Result<HardwareStatus, Error>) -> Bool {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        guard let waiting else { return false }
        waiting.resume(with: result)
        return true
    }
}

@MainActor
final class SystemCoolingService: CoolingService {
    private var connection: NSXPCConnection?
    private lazy var reader = SMCFanHardware()
    private let reads = DispatchQueue(label: "hop.hardware.readings")
    private var appID: String? {
        guard let identifier = Bundle.main.bundleIdentifier,
              HardwareIdentity.applications.contains(identifier) else { return nil }
        return identifier
    }
    // SPEC: docs/spec.md — Cooling service state is read off the main thread.
    private let statusQueue = DispatchQueue(label: "hop.hardware.service-state")
    private var cachedState: CoolingServiceState?
    private var readTicket: UInt64 = 0
    private var appliedTicket: UInt64 = 0
    private var team: String??
    private var service: SMAppService? {
        appID.map { SMAppService.daemon(plistName: $0 + ".hardware.plist") }
    }
    var state: CoolingServiceState { cachedState ?? .unavailable }
    var stateKnown: Bool { cachedState != nil || appID == nil }

    private nonisolated static func status(plist: String) -> CoolingServiceState {
        switch SMAppService.daemon(plistName: plist).status {
        case .enabled: return .enabled
        case .requiresApproval: return .approval
        case .notRegistered, .notFound: return .missing
        default: return .unavailable
        }
    }

    func readState() async -> CoolingServiceState {
        guard let appID else { cachedState = .unavailable; return .unavailable }
        readTicket &+= 1
        let ticket = readTicket
        let plist = appID + ".hardware.plist"
        let value = await withCheckedContinuation { continuation in
            statusQueue.async { continuation.resume(returning: Self.status(plist: plist)) }
        }
        if ticket > appliedTicket { appliedTicket = ticket; cachedState = value }
        return value
    }

    private func ownTeam() async -> String? {
        if let team { return team }
        let value = await withCheckedContinuation { continuation in
            statusQueue.async { continuation.resume(returning: HardwareIdentity.ownTeam()) }
        }
        team = .some(value)
        return value
    }

    func register() async throws {
        let plist = appID.map { $0 + ".hardware.plist" }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                statusQueue.async {
                    guard HardwareIdentity.ownTeam() != nil else {
                        continuation.resume(throwing: HardwareReason.unsignedBuild); return
                    }
                    guard let plist else { continuation.resume(throwing: HardwareReason.serviceMissing); return }
                    do { try SMAppService.daemon(plistName: plist).register(); continuation.resume() }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } catch {
            _ = await readState()
            throw error
        }
        _ = await readState()
    }

    func unregister() async throws {
        guard let service else { throw HardwareReason.serviceMissing }
        do { try await service.unregister() }
        catch { _ = await readState(); throw error }
        invalidate()
        _ = await readState()
    }

    func invalidate() {
        let previous = connection
        connection = nil
        previous?.invalidate()
    }

    private func connect() async throws -> NSXPCConnection {
        if let connection { return connection }
        guard await readState() == .enabled, let appID else { throw HardwareReason.serviceApproval }
        let signer = await ownTeam()
        if let connection { return connection }
        guard let team = signer,
              let requirement = HardwareIdentity.requirement(identifier: appID + HardwareIdentity.helperSuffix, team: team)
        else { throw HardwareReason.unsignedBuild }
        let connection = NSXPCConnection(machServiceName: appID + ".hardware", options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: HardwareXPC.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            Task { @MainActor in
                if self?.connection === connection { self?.connection = nil }
            }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        self.connection = connection
        return connection
    }

    func request(_ request: HardwareRequest) async throws -> HardwareStatus {
        let connection = try await connect()
        return try await exchange(request, over: connection)
    }

    private func exchange(_ request: HardwareRequest, over connection: NSXPCConnection) async throws -> HardwareStatus {
        let data = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let gate = HardwareReply(continuation)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in gate.finish(.failure(error)) }) as? HardwareXPC
            else { gate.finish(.failure(HardwareReason.commandFailed)); return }
            proxy.request(data) { response in
                do {
                    guard response.count <= 16384 else { throw HardwareReason.invalid }
                    let value = try JSONDecoder().decode(HardwareStatus.self, from: response)
                    guard value.version == 1, value.fans.count <= 8, value.fans.allSatisfy(\.valid),
                          Set(value.fans.map(\.id)).count == value.fans.count,
                          value.fanFailure?.valid != false, value.fanRecoveryFailure?.valid != false,
                          value.fanKeys.map({ $0.count <= FanKeyReading.keys.count && $0.allSatisfy(\.valid)
                              && Set($0.map(\.key)).count == $0.count }) ?? true,
                          value.temperature.map({ $0.isFinite && (10...130).contains($0) }) ?? true,
                          HardwareConfiguration(fan: value.policy).valid else { throw HardwareReason.protocolMismatch }
                    gate.finish(.success(value))
                } catch { gate.finish(.failure(error)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + request.replyTimeout) {
                if gate.finish(.failure(HardwareReason.commandFailed)) { connection.invalidate() }
            }
        }
    }

    func localDiagnostics() async -> [FanKeyReading] {
        let reader = reader
        return await withCheckedContinuation { continuation in
            reads.async { continuation.resume(returning: reader.diagnosticKeys()) }
        }
    }

    func localStatus() async -> HardwareStatus {
        let reader = reader
        return await withCheckedContinuation { continuation in
            reads.async {
                let reading = reader.read()
                var status = HardwareStatus()
                status.fans = reading.fans; status.temperature = reading.temperature
                status.supportsControl = reading.supportsControl
                status.fanAvailability = reading.availability
                continuation.resume(returning: status)
            }
        }
    }
}
