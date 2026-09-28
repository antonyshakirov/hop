import Foundation
import HopCore
import NetworkExtension
import Security
import os.log

/// SPEC: docs/spec.md — "Network access".
final class FilterDataProvider: NEFilterDataProvider {
    private let log = Logger(subsystem: "com.antonshakirov.minimo.netfilter", category: "filter")
    private let queue = DispatchQueue(label: "netfilter.resolve")
    private var resolved: [String: Set<String>] = [:]
    private var cachedRules: (data: Data?, rules: [NetworkRule]) = (nil, [])
    private var timer: DispatchSourceTimer?

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        let outbound = NENetworkRule(remoteNetwork: nil, remotePrefix: 0, localNetwork: nil,
                                     localPrefix: 0, protocol: .any, direction: .outbound)
        let settings = NEFilterSettings(rules: [NEFilterRule(networkRule: outbound, action: .filterData)],
                                        defaultAction: .allow)
        apply(settings) { [log] error in
            log.info("filter started, error: \(String(describing: error), privacy: .public)")
            completionHandler(error)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 60)
        timer.setEventHandler { [weak self] in self?.refreshAddresses() }
        timer.resume()
        self.timer = timer
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("filter stopped, reason: \(reason.rawValue, privacy: .public)")
        timer?.cancel()
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socket = flow as? NEFilterSocketFlow,
              let endpoint = socket.remoteEndpoint as? NWHostEndpoint else { return .allow() }
        let owner = Self.signing(flow.sourceAppAuditToken)
        let process = Self.signing(socket.sourceProcessAuditToken)
        let apps = [owner.id, process.id].compactMap { $0 }
        let current = NetworkFlow(apps: apps, hostname: socket.remoteHostname, address: endpoint.hostname)
        #if DEBUG
        // SPEC: docs/spec.md — "Network access", a stopped filter (dev builds only).
        if current.address == "192.0.2.1" { exit(3) }
        #endif
        let addresses = queue.sync { resolved }
        let ruled = NetworkRules.ruled(current, rules: rules(), addresses: addresses)
        let service = FilterService.shared
        if ruled == nil, let app = apps.first, socket.socketProtocol == IPPROTO_TCP, service.asking {
            let key = app + " " + (current.hostname ?? current.address)
            if let answer = service.recentAnswer(key) { return answer == .deny ? .drop() : .allow() }
            service.provider = self
            service.ask(key: key, sighting: NetworkSighting(
                app: app, path: owner.path ?? process.path, host: current.hostname, address: current.address,
                port: endpoint.port, verdict: .allow, last: Date()), flow: flow)
            service.record(app: app, path: owner.path ?? process.path, host: current.hostname,
                           address: current.address, port: endpoint.port, verdict: .allow)
            return .pause()
        }
        let verdict = ruled ?? .allow
        log.debug("""
            \(apps.joined(separator: ","), privacy: .public) → \(current.hostname ?? "-", privacy: .public) \
            \(current.address, privacy: .public):\(endpoint.port, privacy: .public) \(verdict.rawValue, privacy: .public)
            """)
        if let app = apps.first {
            FilterService.shared.record(app: app, path: owner.path ?? process.path, host: current.hostname,
                                        address: current.address, port: endpoint.port, verdict: verdict)
        }
        return verdict == .deny ? .drop() : .allow()
    }

    private func rules() -> [NetworkRule] {
        let data = filterConfiguration.vendorConfiguration?[NetworkRules.configurationKey] as? Data
        if data != cachedRules.data {
            cachedRules = (data, NetworkRules.decode(data))
            queue.async { [weak self] in self?.refreshAddresses() }
        }
        return cachedRules.rules
    }

    private func refreshAddresses() {
        let hosts = NetworkRules.hostsToResolve(cachedRules.rules)
        var next: [String: Set<String>] = [:]
        for host in hosts { next[host] = Self.addresses(of: host) }
        resolved = next
    }

    private static func signing(_ token: Data?) -> (id: String?, path: String?) {
        guard let token else { return (nil, nil) }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token] as CFDictionary, [], &code)
                == errSecSuccess, let code else { return (nil, nil) }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return (nil, nil) }
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any]
        return (dict?[kSecCodeInfoIdentifier as String] as? String,
                (dict?[kSecCodeInfoMainExecutable as String] as? URL)?.path)
    }

    private static func addresses(of host: String) -> Set<String> {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0 else { return [] }
        defer { freeaddrinfo(result) }
        var found: Set<String> = []
        var cursor = result
        while let entry = cursor {
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &name, socklen_t(name.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                found.insert(String(cString: name))
            }
            cursor = entry.pointee.ai_next
        }
        return found
    }
}
