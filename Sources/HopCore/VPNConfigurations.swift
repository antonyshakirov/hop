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
    public var state: State

    public init(id: String, name: String, bundleIdentifier: String?, state: State) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.state = state
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
