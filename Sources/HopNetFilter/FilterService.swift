import Foundation
import HopCore
import NetworkExtension
import Security

/// SPEC: docs/spec.md — "Network access", who may talk to the filter.
final class FilterService: NSObject, NSXPCListenerDelegate, NetworkFilterXPC {
    static let shared = FilterService()

    private let queue = DispatchQueue(label: "netfilter.sightings")
    private var log = NetworkSightings()
    private var listener: NSXPCListener?

    func start() {
        guard listener == nil,
              let settings = Bundle.main.object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any],
              let name = settings["NEMachServiceName"] as? String else { return }
        let listener = NSXPCListener(machServiceName: name)
        listener.delegate = self
        listener.resume()
        self.listener = listener
    }

    func record(app: String, path: String?, host: String?, address: String, port: String,
                verdict: NetworkRule.Action) {
        let now = Date()
        queue.async { self.log.record(app: app, path: path, host: host, address: address, port: port,
                                      verdict: verdict, at: now) }
    }

    func sightings(reply: @escaping (Data) -> Void) {
        queue.async { reply(NetworkSightings.encode(self.log.all)) }
    }

    // MARK: questions about new connections

    static let answerWait: TimeInterval = 30
    private var asker: NSXPCConnection?
    private var waiting: [String: [NEFilterFlow]] = [:]
    private var answered: [String: (NetworkRule.Action, Date)] = [:]
    weak var provider: NEFilterDataProvider?

    var asking: Bool { queue.sync { asker != nil } }

    /// Only the connection that asks may stop asking; nobody takes over a live one.
    func setAsking(_ on: Bool) {
        guard let connection = NSXPCConnection.current() else { return }
        queue.async {
            if on, self.asker == nil || self.asker === connection {
                self.asker = connection
            } else if !on, self.asker === connection {
                self.asker = nil
            }
        }
    }

    func recentAnswer(_ key: String) -> NetworkRule.Action? {
        queue.sync {
            guard let (action, at) = answered[key], Date().timeIntervalSince(at) < 60 else { return nil }
            return action
        }
    }

    func ask(key: String, sighting: NetworkSighting, flow: NEFilterFlow) {
        queue.async {
            if self.waiting[key] != nil {
                self.waiting[key]?.append(flow)
                return
            }
            self.waiting[key] = [flow]
            guard let proxy = self.asker?.remoteObjectProxyWithErrorHandler({ _ in
                self.resolve(key, nil)
            }) as? NetworkFilterAskerXPC else { return self.resolve(key, nil) }
            let data = NetworkSightings.encode([sighting])
            proxy.ask(data) { answer in
                self.resolve(key, NetworkRule.Action(rawValue: answer))
            }
            self.queue.asyncAfter(deadline: .now() + Self.answerWait) { self.resolve(key, nil) }
        }
    }

    // SPEC: docs/spec.md — "Network access", questions: no answer lets it through.
    private func resolve(_ key: String, _ answer: NetworkRule.Action?) {
        queue.async {
            guard let flows = self.waiting.removeValue(forKey: key) else { return }
            let action = answer ?? .allow
            if let answer { self.answered[key] = (answer, Date()) }
            for flow in flows {
                self.provider?.resumeFlow(flow, with: action == .deny ? NEFilterNewFlowVerdict.drop()
                                                                      : NEFilterNewFlowVerdict.allow())
            }
        }
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // SPEC: docs/spec.md — "Network access": Hop itself, as shipped with Developer ID.
        guard let team = Self.ownTeam, let own = Bundle.main.bundleIdentifier,
              own.hasSuffix(".netfilter") else { return false }
        let app = String(own.dropLast(".netfilter".count))
        connection.setCodeSigningRequirement("""
            identifier "\(app)" and anchor apple generic \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "\(team)"
            """)
        connection.exportedInterface = NSXPCInterface(with: NetworkFilterXPC.self)
        connection.remoteObjectInterface = NSXPCInterface(with: NetworkFilterAskerXPC.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self, weak connection] in
            self?.queue.async { if self?.asker === connection { self?.asker = nil } }
        }
        connection.resume()
        return true
    }

    private static let ownTeam: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }()
}
