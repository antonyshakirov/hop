import Foundation
import HopCore
import NetworkExtension
import Security
import os
import os.log

/// SPEC: docs/spec.md — "Network access".
final class FilterDataProvider: NEFilterDataProvider {
    private struct State {
        var data: Data?
        var rules: [NetworkRule] = []
        var index = NetworkRuleIndex([])
        var resolved: [String: Set<String>] = [:]
        var pending: Set<String> = []
        /// When each name asked for by a connection was last looked up.
        var tried: [String: Date] = [:]
        var debugExit = false
    }

    private let log = Logger(subsystem: "com.antonshakirov.minimo.netfilter", category: "filter")
    // SPEC: docs/spec.md — "Network access": a connection never waits on a lookup.
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let lookups = DispatchQueue(label: "netfilter.lookups", qos: .utility)
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
        let timer = DispatchSource.makeTimerSource(queue: lookups)
        timer.schedule(deadline: .now(), repeating: 60)
        timer.setEventHandler { [weak self] in self?.lookUpRuleHosts() }
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
        refreshRules()
        let (index, resolved, debugExit) = state.withLock { ($0.index, $0.resolved, $0.debugExit) }
        #if DEBUG
        // SPEC: docs/spec.md — "Network access", a stopped filter (dev builds, on request).
        if debugExit && current.address == "192.0.2.1" { exit(3) }
        #endif
        let result = index.ruled(current, resolved: resolved)
        if let name = result.lookUp { lookUp(name) }
        let path = owner.path ?? process.path
        let service = FilterService.shared
        if result.action == nil, let app = apps.first, socket.socketProtocol == IPPROTO_TCP, service.asking {
            let key = app + " " + (current.hostname ?? current.address)
            if let answer = service.recentAnswer(key) { return answer == .deny ? .drop() : .allow() }
            service.provider = self
            service.ask(key: key, sighting: NetworkSighting(
                app: app, path: path, host: current.hostname, address: current.address,
                port: endpoint.port, verdict: .allow, last: Date()), flow: flow)
            service.record(app: app, path: path, host: current.hostname, address: current.address,
                           port: endpoint.port, verdict: .allow)
            return .pause()
        }
        let verdict = result.action ?? .allow
        log.debug("""
            \(apps.joined(separator: ","), privacy: .public) → \(current.hostname ?? "-", privacy: .public) \
            \(current.address, privacy: .public):\(endpoint.port, privacy: .public) \(verdict.rawValue, privacy: .public)
            """)
        if let app = apps.first {
            service.record(app: app, path: path, host: current.hostname, address: current.address,
                           port: endpoint.port, verdict: verdict)
        }
        return verdict == .deny ? .drop() : .allow()
    }

    private func refreshRules() {
        let configuration = filterConfiguration.vendorConfiguration
        let data = configuration?[NetworkRules.configurationKey] as? Data
        guard state.withLock({ $0.data != data }) else { return }
        let rules = NetworkRules.decode(data)
        let index = NetworkRuleIndex(rules)
        let debugExit = configuration?["debugExit"] as? Bool ?? false
        state.withLock {
            $0.data = data
            $0.rules = rules
            $0.index = index
            $0.debugExit = debugExit
        }
        lookups.async { [weak self] in self?.lookUpRuleHosts() }
    }

    /// A name found is asked again after a minute, one that was not after 30 s:
    /// sites move, and a lookup made offline must not stand for ever.
    private func lookUp(_ name: String) {
        let now = Date()
        let fresh = state.withLock { state -> Bool in
            let wait: TimeInterval = state.resolved[name] == nil ? 30 : 60
            guard state.pending.count < 100, !state.pending.contains(name),
                  now.timeIntervalSince(state.tried[name] ?? .distantPast) > wait else { return false }
            state.pending.insert(name)
            state.tried[name] = now
            return true
        }
        guard fresh else { return }
        lookups.async { [weak self] in
            let found = Self.addresses(of: name)
            self?.state.withLock {
                $0.pending.remove(name)
                $0.resolved[name] = found.isEmpty ? nil : found
            }
        }
    }

    private func lookUpRuleHosts() {
        let rules = state.withLock { $0.rules }
        var found: [String: Set<String>] = [:]
        for host in NetworkRules.hostsToResolve(rules) {
            let addresses = Self.addresses(of: host)
            if !addresses.isEmpty { found[host] = addresses }
        }
        let fresh = found
        let hourAgo = Date().addingTimeInterval(-3600)
        state.withLock { state in
            state.tried = state.tried.filter { $0.value > hourAgo }
            var merged = fresh
            for name in state.tried.keys where merged[name] == nil {
                merged[name] = state.resolved[name]
            }
            state.resolved = merged
        }
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
