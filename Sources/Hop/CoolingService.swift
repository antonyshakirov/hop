import AppKit
import Foundation
import HopHardwareKit
import ServiceManagement

enum CoolingServiceState { case enabled, approval, missing, unavailable }

@MainActor
protocol CoolingService: AnyObject {
    var state: CoolingServiceState { get }
    func register() throws
    func unregister() async throws
    func request(_ request: HardwareRequest) async throws -> HardwareStatus
    func localStatus() async -> HardwareStatus
    func invalidate()
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
    private var service: SMAppService? {
        appID.map { SMAppService.daemon(plistName: $0 + ".hardware.plist") }
    }
    var state: CoolingServiceState {
        guard let service else { return .unavailable }
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .approval
        case .notRegistered, .notFound: return .missing
        default: return .unavailable
        }
    }

    func register() throws {
        guard HardwareIdentity.ownTeam() != nil else { throw HardwareReason.unsignedBuild }
        guard let service else { throw HardwareReason.serviceMissing }
        try service.register()
    }

    func unregister() async throws {
        guard let service else { throw HardwareReason.serviceMissing }
        try await service.unregister()
        invalidate()
    }

    func invalidate() {
        let previous = connection
        connection = nil
        previous?.invalidate()
    }

    private func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        guard state == .enabled, let appID else { throw HardwareReason.serviceApproval }
        guard let team = HardwareIdentity.ownTeam(),
              let requirement = HardwareIdentity.requirement(identifier: appID + HardwareIdentity.helperSuffix, team: team)
        else { throw HardwareReason.unsignedBuild }
        let connection = NSXPCConnection(machServiceName: appID + ".hardware", options: .privileged)
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: HardwareXPC.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            Task { @MainActor in if self?.connection === connection { self?.connection = nil } }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        self.connection = connection
        return connection
    }

    func request(_ request: HardwareRequest) async throws -> HardwareStatus {
        let connection = try connect(), data = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let gate = HardwareReply(continuation)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in gate.finish(.failure(error)) }) as? HardwareXPC
            else { gate.finish(.failure(HardwareReason.commandFailed)); return }
            proxy.request(data) { response in
                do {
                    guard response.count <= 16384 else { throw HardwareReason.invalid }
                    let value = try JSONDecoder().decode(HardwareStatus.self, from: response)
                    guard value.version == 1, value.fans.count <= 8, value.fans.allSatisfy(\.valid),
                          value.temperature.map({ $0.isFinite && (10...130).contains($0) }) ?? true,
                          HardwareConfiguration(fan: value.policy).valid else { throw HardwareReason.protocolMismatch }
                    gate.finish(.success(value))
                } catch { gate.finish(.failure(error)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if gate.finish(.failure(HardwareReason.commandFailed)) { connection.invalidate() }
            }
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
                continuation.resume(returning: status)
            }
        }
    }
}
