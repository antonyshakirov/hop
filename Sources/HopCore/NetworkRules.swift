import Foundation

/// SPEC: docs/spec.md — "Network access".
public struct NetworkRule: Codable, Hashable, Sendable {
    public enum Action: String, Codable, Sendable {
        case allow, deny
    }

    /// The code-signing identifier of the program, e.g. `com.apple.curl`.
    public var app: String
    /// nil covers every destination of the program.
    public var host: String?
    public var action: Action

    public init(app: String, host: String? = nil, action: Action) {
        self.app = app
        self.host = host.map(NetworkRules.normalized)
        self.action = action
    }
}

/// One outgoing connection as the filter sees it.
public struct NetworkFlow: Sendable {
    public var apps: [String]
    public var hostname: String?
    public var address: String

    public init(apps: [String], hostname: String?, address: String) {
        self.apps = apps
        self.hostname = hostname.map(NetworkRules.normalized)
        self.address = address
    }
}

public enum NetworkRules {
    public static let configurationKey = "rules"

    /// A rule for a destination beats a rule for the whole program; between
    /// equals, deny wins. With no rule the connection goes through.
    public static func verdict(for flow: NetworkFlow, rules: [NetworkRule],
                               addresses: [String: Set<String>] = [:]) -> NetworkRule.Action {
        let mine = rules.filter { flow.apps.contains($0.app) }
        let forHost = mine.filter { rule in
            guard let host = rule.host else { return false }
            return covers(host, flow.hostname) || addresses[host]?.contains(flow.address) == true
                || host == flow.address
        }
        if !forHost.isEmpty { return forHost.contains { $0.action == .deny } ? .deny : .allow }
        let whole = mine.filter { $0.host == nil }
        return whole.contains { $0.action == .deny } ? .deny : .allow
    }

    /// Hosts the filter has to resolve itself: a program that looks an address
    /// up on its own reaches the filter with the address and no name.
    public static func hostsToResolve(_ rules: [NetworkRule]) -> Set<String> {
        Set(rules.compactMap(\.host).filter { !isAddress($0) })
    }

    public static func encode(_ rules: [NetworkRule]) -> Data {
        (try? JSONEncoder().encode(rules)) ?? Data("[]".utf8)
    }

    public static func decode(_ data: Data?) -> [NetworkRule] {
        guard let data, let rules = try? JSONDecoder().decode([NetworkRule].self, from: data) else { return [] }
        return rules
    }

    static func covers(_ ruleHost: String, _ hostname: String?) -> Bool {
        guard let hostname else { return false }
        return hostname == ruleHost || hostname.hasSuffix("." + ruleHost)
    }

    static func isAddress(_ host: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }

    static func normalized(_ host: String) -> String {
        var value = host.lowercased().trimmingCharacters(in: .whitespaces)
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }
}
