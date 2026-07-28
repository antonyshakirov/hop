import Foundation

/// One VPN as macOS knows it: a configuration in the system's network settings,
/// not an app. Anything that registers itself there — a downloaded client, a
/// corporate IKEv2 profile, a WireGuard tunnel — shows up the same way, which is
/// why the module needs no per-vendor support and nothing to add by hand.
public struct VPNConfiguration: Equatable, Identifiable, Sendable {
    public enum State: String, Equatable, Sendable {
        case connected, connecting, disconnecting, disconnected, unknown

        /// Only a settled connection counts as on — a tunnel still negotiating is
        /// not yet protecting anything.
        public var isOn: Bool { self == .connected }
        /// The in-between states, where the row shows motion rather than a verdict.
        public var isBusy: Bool { self == .connecting || self == .disconnecting }
    }

    /// The configuration's own identifier, which is what the system command takes.
    public let id: String
    /// What the user named it: "hidemy.name vpn (OpenVPN)", "Germany".
    public let name: String
    /// The app that owns the configuration, when one does — used to open its
    /// window on request. nil for a profile with no app behind it.
    public let bundleIdentifier: String?
    /// What that app is called on this Mac, filled in by the app layer. The two
    /// names differ and both matter: an app may be called one thing while the
    /// configuration it created is called "Germany" — showing only the second
    /// looks like Hop invented a country out of nowhere (Anton, 2026-07-29).
    public var appName: String?
    public var state: State

    public init(id: String, name: String, bundleIdentifier: String?,
                appName: String? = nil, state: State) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.state = state
    }

    /// What the row leads with: the app when it is known, the configuration
    /// otherwise.
    public var title: String { appName ?? name }

    /// The short tail beside the title — a country, a protocol, a profile — with
    /// whatever the app's name already said stripped out.
    ///
    /// A client tends to name its configuration after itself ("hidemy.name vpn
    /// (OpenVPN)" for an app called "hidemy.name VPN"), and printing both in full
    /// filled the row with the same words twice (Anton, 2026-07-29).
    public var subtitle: String? {
        guard let appName else { return nil }
        return VPNConfigurations.tail(of: name, after: appName)
    }
}

/// Reads what `scutil --nc list` and `scutil --nc status` say.
///
/// Parsing rather than the NetworkExtension API on purpose: `NEVPNManager` can
/// only see configurations the calling app created itself, and reaching another
/// app's tunnel needs an entitlement that comes with a paid developer account.
/// `scutil` is the same door the system's own menu-bar switch uses.
public enum VPNConfigurations {

    /// One line of `scutil --nc list`:
    ///
    ///     * (Connected)   6A7852E0-… VPN (hidemyname.vpn) "hidemy.name vpn"  [VPN:hidemyname.vpn]
    ///
    /// The quoted part is the user's own name for it; the identifier before it is
    /// what the start/stop commands take.
    public static func parseList(_ output: String) -> [VPNConfiguration] {
        var out: [VPNConfiguration] = []
        for line in output.split(separator: "\n").map(String.init) {
            guard line.contains("VPN") else { continue }
            guard let id = identifier(in: line) else { continue }
            guard let name = quoted(in: line), !name.isEmpty else { continue }
            out.append(VPNConfiguration(id: id,
                                        name: name,
                                        bundleIdentifier: bundleIdentifier(in: line),
                                        state: state(in: line)))
        }
        return out
    }

    /// The first word of `scutil --nc status`, which is the state on its own line.
    public static func parseStatus(_ output: String) -> VPNConfiguration.State {
        let first = output.split(separator: "\n").first.map(String.init) ?? ""
        return state(named: first.trimmingCharacters(in: .whitespaces))
    }

    /// Words that describe the plumbing rather than the connection. A protocol
    /// name in the row tells the user nothing they can act on — what they want to
    /// see there is the country (Anton, 2026-07-29).
    private static let technical: Set<String> = [
        "openvpn", "ikev2", "ikev1", "ipsec", "l2tp", "pptp", "wireguard", "wg",
        "tcp", "udp", "vpn", "proxy", "tunnel",
    ]

    /// What `name` says that `appName` does not. nil when it says nothing new, or
    /// nothing but plumbing.
    static func tail(of name: String, after appName: String) -> String? {
        let words = appName.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." })
            .map(String.init)
        var kept: [String] = []
        for token in name.split(separator: " ").map(String.init) {
            let bare = token.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: "()[]{}"))
            if words.contains(bare) { continue }
            // keep the token as written, minus the brackets a client wraps a
            // protocol in
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}"))
            if !cleaned.isEmpty { kept.append(cleaned) }
        }
        let meaningful = kept.filter { token in
            let bare = token.lowercased().trimmingCharacters(
                in: CharacterSet.alphanumerics.inverted)
            return !technical.contains(bare)
        }
        let tail = meaningful.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? nil : tail
    }

    // MARK: - Pieces of a line

    /// The UUID that names the configuration to the system.
    static func identifier(in line: String) -> String? {
        for token in line.split(separator: " ").map(String.init) where token.count == 36 {
            let parts = token.split(separator: "-")
            if parts.count == 5, UUID(uuidString: token) != nil { return token }
        }
        return nil
    }

    /// The display name, in quotes.
    static func quoted(in line: String) -> String? {
        guard let start = line.firstIndex(of: "\""),
              let end = line[line.index(after: start)...].firstIndex(of: "\"") else { return nil }
        return String(line[line.index(after: start)..<end])
    }

    /// The owning app, written in parentheses right after the word VPN.
    static func bundleIdentifier(in line: String) -> String? {
        guard let range = line.range(of: "VPN ("),
              let end = line[range.upperBound...].firstIndex(of: ")") else { return nil }
        let value = String(line[range.upperBound..<end]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// The state, in parentheses at the head of the line.
    static func state(in line: String) -> VPNConfiguration.State {
        guard let start = line.firstIndex(of: "("),
              let end = line[start...].firstIndex(of: ")") else { return .unknown }
        return state(named: String(line[line.index(after: start)..<end]))
    }

    private static func state(named raw: String) -> VPNConfiguration.State {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "connected": return .connected
        case "connecting": return .connecting
        case "disconnecting": return .disconnecting
        case "disconnected": return .disconnected
        default: return .unknown
        }
    }
}
