import Foundation
import HopHardwareKit
import Darwin
import SystemConfiguration

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
            if let ownerUID, ownerUID != Self.activeUser() {
                coordinator.shutdown(); self.ownerUID = nil
            }
            coordinator.tick()
        }
        timer.resume(); self.timer = timer
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termination.setEventHandler { [weak self] in self?.coordinator.shutdown(); exit(0) }
        termination.resume(); self.termination = termination
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard Self.activeUser() == connection.effectiveUserIdentifier else { return false }
        connection.setCodeSigningRequirement(requirement)
        let session = HardwareSession(service: self, uid: connection.effectiveUserIdentifier)
        connection.exportedInterface = NSXPCInterface(with: HardwareXPC.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak self] in
            self?.queue.async { self?.coordinator.disconnect(owner: session.owner) }
        }
        connection.interruptionHandler = connection.invalidationHandler
        connection.resume()
        return true
    }

    static func activeUser() -> uid_t? {
        var uid: uid_t = 0, gid: gid_t = 0
        guard let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?,
              name != "loginwindow", uid != 0 else { return nil }
        return uid
    }
}

final class HardwareSession: NSObject, HardwareXPC {
    let owner = UUID()
    private unowned let service: HardwareService
    private let uid: uid_t
    init(service: HardwareService, uid: uid_t) { self.service = service; self.uid = uid }

    func request(_ data: Data, reply: @escaping (Data) -> Void) {
        service.queue.async { [self] in
            var status: HardwareStatus
            do {
                guard HardwareService.activeUser() == uid else {
                    service.coordinator.disconnect(owner: owner)
                    throw HardwareReason.unauthorized
                }
                let request = try HardwareRequest.decode(data)
                status = service.coordinator.handle(request, owner: owner, user: uid)
                if request.operation == .configure, status.active, status.reason == nil { service.ownerUID = uid }
            } catch {
                status = service.coordinator.handle(HardwareRequest(.status), owner: owner)
                status.reason = error as? HardwareReason ?? .invalid
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
