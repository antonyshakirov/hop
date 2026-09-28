import Foundation

/// SPEC: docs/spec.md — "Network access".
public struct NetworkRule: Codable, Hashable, Sendable {
    public enum Action: String, Codable, Sendable {
        case allow, deny
    }

    /// Stands for every program in a rule about one address.
    public static let anyProgram = "*"

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
        let forHost = rules.filter { rule in
            guard let host = rule.host, rule.app == NetworkRule.anyProgram || flow.apps.contains(rule.app)
            else { return false }
            return covers(host, flow.hostname) || addresses[host]?.contains(flow.address) == true
                || host == flow.address
        }
        let own = forHost.filter { $0.app != NetworkRule.anyProgram }
        let deciding = own.isEmpty ? forHost : own
        if !deciding.isEmpty { return deciding.contains { $0.action == .deny } ? .deny : .allow }
        let whole = rules.filter { $0.host == nil && flow.apps.contains($0.app) }
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

/// SPEC: docs/spec.md — "Network access", rules from a file.
public enum NetworkRuleFile {
    /// JSON as Hop saves it, or text: one address per line (blocked for every
    /// program), a hosts file, or `program address [allow|block]` lines where
    /// `*` as the address stands for the whole program.
    public static func parse(_ text: String) -> [NetworkRule] {
        if let data = text.data(using: .utf8),
           let rules = try? JSONDecoder().decode([NetworkRule].self, from: data) {
            return rules
        }
        var rules: [NetworkRule] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            var words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }
            var action = NetworkRule.Action.deny
            if let last = words.last?.lowercased(), ["allow", "block", "deny"].contains(last), words.count > 1 {
                action = last == "allow" ? .allow : .deny
                words.removeLast()
            }
            if let first = words.first?.lowercased(), ["allow", "block", "deny"].contains(first), words.count > 1 {
                action = first == "allow" ? .allow : .deny
                words.removeFirst()
            }
            if NetworkRules.isAddress(words[0]) {
                // a hosts file: the address it points names at, then the names
                for name in words.dropFirst() where name != "localhost" && !name.hasSuffix(".localdomain") {
                    rules.append(NetworkRule(app: NetworkRule.anyProgram, host: name, action: .deny))
                }
                continue
            }
            switch words.count {
            case 1 where words[0] != "*":
                rules.append(NetworkRule(app: NetworkRule.anyProgram, host: words[0], action: action))
            case 2... where words[1] == "*":
                rules.append(NetworkRule(app: words[0], action: action))
            case 2...:
                rules.append(NetworkRule(app: words[0], host: words[1], action: action))
            default:
                break
            }
        }
        return rules
    }

    public static func text(_ rules: [NetworkRule]) -> String {
        rules.map { rule in
            "\(rule.app) \(rule.host ?? "*") \(rule.action == .allow ? "allow" : "block")"
        }.joined(separator: "\n") + "\n"
    }

    /// The file wins where it names the same program and address.
    public static func merge(_ current: [NetworkRule], _ incoming: [NetworkRule]) -> [NetworkRule] {
        let replaced = Set(incoming.map { "\($0.app) \($0.host ?? "")" })
        return current.filter { !replaced.contains("\($0.app) \($0.host ?? "")") } + incoming
    }
}
