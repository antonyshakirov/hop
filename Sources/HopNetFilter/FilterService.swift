import Foundation
import HopCore
import NetworkExtension
import Security

/// SPEC: docs/spec.md — "Network access". Keeps what the filter saw and hands it
/// to the app over the extension's Mach service — only to code signed by the
/// same team.
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

    func setAsking(_ on: Bool) {
        let connection = NSXPCConnection.current()
        queue.async { self.asker = on ? connection : nil }
    }

    /// An answer given a moment ago still stands while its rule is on its way.
    func recentAnswer(_ key: String) -> NetworkRule.Action? {
        queue.sync {
            guard let (action, at) = answered[key], Date().timeIntervalSince(at) < 60 else { return nil }
            return action
        }
    }

    /// Holds the flow; the first flow of a key asks, the rest wait with it.
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

    /// No answer lets the connection through: a question must never hang the Mac.
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
        guard let team = Self.ownTeam else { return false }
        connection.setCodeSigningRequirement("anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
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
