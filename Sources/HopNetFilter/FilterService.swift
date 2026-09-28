import Foundation
import HopCore
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

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let team = Self.ownTeam else { return false }
        connection.setCodeSigningRequirement("anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
        connection.exportedInterface = NSXPCInterface(with: NetworkFilterXPC.self)
        connection.exportedObject = self
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
