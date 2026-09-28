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
    /// At most this many rule hosts are looked up by the filter itself.
    public static let resolveLimit = 200

    /// Destination rules beat the program's switch; deny wins between equals.
    public static func verdict(for flow: NetworkFlow, rules: [NetworkRule],
                               addresses: [String: Set<String>] = [:]) -> NetworkRule.Action {
        ruled(flow, rules: rules, addresses: addresses) ?? .allow
    }

    /// nil when no rule speaks about this connection: the one to ask about.
    public static func ruled(_ flow: NetworkFlow, rules: [NetworkRule],
                             addresses: [String: Set<String>] = [:]) -> NetworkRule.Action? {
        NetworkRuleIndex(rules).ruled(flow, resolved: addresses).action
    }

    /// Rule hosts the filter looks up itself: one program's, and allows for every
    /// program. A block list for every program is matched by name, never looked up.
    public static func hostsToResolve(_ rules: [NetworkRule]) -> Set<String> {
        var hosts: [String] = []
        var seen = Set<String>()
        let allowsFirst = rules.filter { $0.action == .allow } + rules.filter { $0.action == .deny }
        for rule in allowsFirst where rule.app != NetworkRule.anyProgram || rule.action == .allow {
            guard let host = rule.host, !isAddress(host), seen.insert(host).inserted else { continue }
            hosts.append(host)
            if hosts.count == resolveLimit { break }
        }
        return Set(hosts)
    }

    /// A name lookup made for a program, which macOS charges to that program:
    /// always let through and not listed, or a blocked program could not even
    /// learn the address of a host it is allowed to reach.
    public static func isNameLookup(process: String?, port: String) -> Bool {
        process == "com.apple.mDNSResponder" || port == "53" || port == "853"
    }

    public static func encode(_ rules: [NetworkRule]) -> Data {
        (try? JSONEncoder().encode(rules)) ?? Data("[]".utf8)
    }

    public static func decode(_ data: Data?) -> [NetworkRule] {
        guard let data, let rules = try? JSONDecoder().decode([NetworkRule].self, from: data) else { return [] }
        return rules
    }

    static func isAddress(_ host: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        let bare = host.split(separator: "%").first.map(String.init) ?? host
        return inet_pton(AF_INET, bare, &v4) == 1 || inet_pton(AF_INET6, bare, &v6) == 1
    }

    static func normalized(_ host: String) -> String {
        var value = host.lowercased().trimmingCharacters(in: .whitespaces)
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }
}

/// Rules looked up by host and by program: a connection costs a few dictionary
/// reads however many rules a block list brought.
public struct NetworkRuleIndex: Sendable {
    private var byHost: [String: [NetworkRule]] = [:]
    private var whole: [String: [NetworkRule]] = [:]

    public init(_ rules: [NetworkRule]) {
        for rule in rules {
            if let host = rule.host {
                byHost[host, default: []].append(rule)
            } else if rule.app != NetworkRule.anyProgram {
                whole[rule.app, default: []].append(rule)
            }
        }
    }

    /// A program names its own host, so an allow by name holds only for an address
    /// the filter found for that name itself; `lookUp` is the name to find.
    public func ruled(_ flow: NetworkFlow, resolved: [String: Set<String>])
        -> (action: NetworkRule.Action?, lookUp: String?) {
        var byName: [NetworkRule] = []
        var matched: [NetworkRule] = []
        if let name = flow.hostname {
            var labels = name.split(separator: ".")
            while !labels.isEmpty {
                byName += byHost[labels.joined(separator: "."), default: []]
                labels.removeFirst()
            }
        }
        matched += byHost[flow.address, default: []]
        for (host, addresses) in resolved where addresses.contains(flow.address) {
            matched += byHost[host, default: []]
        }
        let mine: (NetworkRule) -> Bool = { $0.app == NetworkRule.anyProgram || flow.apps.contains($0.app) }
        matched = matched.filter(mine)
        var lookUp: String?
        let confirmed = flow.hostname.map { resolved[$0]?.contains(flow.address) == true } ?? false
        for rule in byName where mine(rule) {
            let sure = confirmed || rule.host.flatMap { resolved[$0] }?.contains(flow.address) == true
            if rule.action == .deny || sure {
                matched.append(rule)
            } else {
                lookUp = flow.hostname
            }
        }
        let own = matched.filter { $0.app != NetworkRule.anyProgram }
        let deciding = own.isEmpty ? matched : own
        if !deciding.isEmpty {
            let deny = deciding.contains { $0.action == .deny }
            return (deny ? .deny : .allow, deny ? lookUp : nil)
        }
        let programs = flow.apps.flatMap { whole[$0, default: []] }
        guard !programs.isEmpty else { return (nil, lookUp) }
        return (programs.contains { $0.action == .deny } ? .deny : .allow, lookUp)
    }
}

/// SPEC: docs/spec.md — "Network access", rules from a file.
public enum NetworkRuleFile {
    public static func parse(_ text: String) -> [NetworkRule] {
        if let data = text.data(using: .utf8),
           let rules = try? JSONDecoder().decode([NetworkRule].self, from: data) {
            return rules.filter { rule in
                guard let host = rule.host else { return rule.app != NetworkRule.anyProgram }
                return blockable(host) || NetworkRules.isAddress(host)
            }
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
                guard words.count > 1 else {
                    rules.append(NetworkRule(app: NetworkRule.anyProgram, host: words[0], action: action))
                    continue
                }
                for name in words.dropFirst() where blockable(name) {
                    rules.append(NetworkRule(app: NetworkRule.anyProgram, host: name, action: .deny))
                }
                continue
            }
            switch words.count {
            case 1 where blockable(words[0]):
                rules.append(NetworkRule(app: NetworkRule.anyProgram, host: words[0], action: action))
            case 1:
                break
            case 2... where words[1] == "*":
                rules.append(NetworkRule(app: words[0], action: action))
            case 2... where blockable(words[1]) || NetworkRules.isAddress(words[1]):
                rules.append(NetworkRule(app: words[0], host: words[1], action: action))
            default:
                break
            }
        }
        return rules
    }

    /// A real host: never the local network's own names nor a whole top-level domain.
    static func blockable(_ name: String) -> Bool {
        let host = NetworkRules.normalized(name)
        guard host.contains("."), !NetworkRules.isAddress(host) else { return false }
        let reserved = ["localhost", "localdomain", "local", "broadcasthost"]
        if reserved.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return false }
        return !host.hasPrefix("ip6-")
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
