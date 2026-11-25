import Foundation
import HopHardwareKit
import Darwin
import SystemConfiguration
import os

// SPEC: docs/spec.md — Protected lid sessions and Cooling controls.
final class HardwareService: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "hop.hardware.owner")
    let coordinator: HardwareCoordinator
    private var listener: NSXPCListener?
    private var timer: DispatchSourceTimer?
    private var termination: DispatchSourceSignal?
    private let appID: String
    private let requirement: String
    var ownerUID: uid_t?
    let clients = ClientRegistry(alive: { HardwareService.process($0.pid) == $0 })
    static let log = Logger(subsystem: "com.antonshakirov.minimo.hardware", category: "lease")

    init(appID: String, requirement: String) {
        self.appID = appID; self.requirement = requirement
        coordinator = HardwareCoordinator(backend: SystemHardwareBackend(), journal: FileHardwareJournal(), application: appID)
    }

    func start() {
        queue.sync { coordinator.recoverAtLaunch() }
        let listener = NSXPCListener(machServiceName: appID + ".hardware")
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 3, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            tracking {
                if let ownerUID = self.ownerUID, ownerUID != Self.activeUser() {
                    self.coordinator.shutdown(); self.ownerUID = nil
                }
                self.releaseDeparted()
                self.coordinator.tick()
            }
        }
        timer.resume(); self.timer = timer
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termination.setEventHandler { [weak self] in self?.coordinator.shutdown(); exit(0) }
        termination.resume(); self.termination = termination
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard Self.activeUser() == connection.effectiveUserIdentifier,
              let process = Self.process(connection.processIdentifier) else { return false }
        connection.setCodeSigningRequirement(requirement)
        let lease = clients.connect(process)
        let session = HardwareSession(service: self, uid: connection.effectiveUserIdentifier, lease: lease)
        connection.exportedInterface = NSXPCInterface(with: HardwareXPC.self)
        connection.exportedObject = session
        // A dropped connection from a live app keeps its lease; only an exited app releases it here.
        connection.invalidationHandler = { [weak self] in
            self?.clients.retire(lease)
            self?.queue.async { self?.tracking { self?.releaseDeparted() } }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        return true
    }

    /// Logs every lease end with its reason, whichever path ended it.
    func tracking<T>(_ body: () throws -> T) rethrows -> T {
        let wasActive = coordinator.leaseActive
        defer {
            if wasActive, !coordinator.leaseActive {
                let reason = coordinator.endReason?.rawValue ?? "none"
                Self.log.notice("lease ended: \(reason, privacy: .public)")
            }
        }
        return try body()
    }

    func releaseDeparted() {
        for owner in clients.departed() { coordinator.disconnect(owner: owner) }
    }

    static func process(_ pid: pid_t) -> ClientProcess? {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard pid > 0, sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0,
              info.kp_proc.p_pid == pid, info.kp_proc.p_stat != SZOMB,
              info.kp_proc.p_flag & P_WEXIT == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return ClientProcess(pid: pid, started: UInt64(start.tv_sec) &* 1_000_000 &+ UInt64(start.tv_usec))
    }

    static func activeUser() -> uid_t? {
        var uid: uid_t = 0, gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
              name != "loginwindow", uid != 0 else { return nil }
        return uid
    }
}

final class HardwareSession: NSObject, HardwareXPC {
    private let lease: ClientLease
    private unowned let service: HardwareService
    private let uid: uid_t
    init(service: HardwareService, uid: uid_t, lease: ClientLease) {
        self.service = service; self.uid = uid; self.lease = lease
    }

    func request(_ data: Data, reply: @escaping (Data) -> Void) {
        let received = ProcessInfo.processInfo.systemUptime
        service.queue.async { [self] in
            let waited = ProcessInfo.processInfo.systemUptime - received
            if waited > 2 { HardwareService.log.notice("request waited \(waited, format: .fixed(precision: 1)) s for the queue") }
            let owner = lease.owner
            let status: HardwareStatus = service.tracking {
                do {
                    guard HardwareService.activeUser() == uid else {
                        service.coordinator.disconnect(owner: owner)
                        throw HardwareReason.unauthorized
                    }
                    guard service.clients.isCurrent(lease) else { throw HardwareReason.busy }
                    service.releaseDeparted()
                    let request = try HardwareRequest.decode(data)
                    let status = service.coordinator.handle(request, owner: owner, user: uid)
                    if request.operation == .configure, status.active, status.reason == nil { service.ownerUID = uid }
                    return status
                } catch {
                    var status = service.coordinator.handle(HardwareRequest(.status), owner: owner)
                    status.reason = error as? HardwareReason ?? .invalid
                    return status
                }
            }
            reply((try? JSONEncoder().encode(status)) ?? Data())
        }
    }
}

if CommandLine.arguments == [CommandLine.arguments[0], "--probe"] {
    let backend = SystemHardwareBackend()
    let observation = backend.observe()
    var status = HardwareStatus()
    status.fans = observation.fans.filter(\.valid)
    status.temperature = observation.freshTemperature
    status.supportsControl = observation.supportsControl
    status.fanAvailability = observation.fanAvailability
    status.fanKeys = backend.diagnosticKeys()
    if let data = try? JSONEncoder().encode(status), let text = String(data: data, encoding: .utf8) { print(text) }
    exit(0)
}
guard geteuid() == 0,
      let identifier = Bundle.main.bundleIdentifier, identifier.hasSuffix(HardwareIdentity.helperSuffix),
      let team = HardwareIdentity.ownTeam() else { exit(1) }
let appID = String(identifier.dropLast(HardwareIdentity.helperSuffix.count))
guard let requirement = HardwareIdentity.requirement(identifier: appID, team: team) else { exit(1) }
let service = HardwareService(appID: appID, requirement: requirement)
service.start()
dispatchMain()
