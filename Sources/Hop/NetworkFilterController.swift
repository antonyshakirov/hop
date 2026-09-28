import AppKit
import Foundation
import HopCore
import NetworkExtension
import SystemExtensions
import os.log

/// SPEC: docs/spec.md — "Network access". Installs the filter extension, turns
/// the system's content filter on and off, and hands it the rules.
@MainActor
final class NetworkFilterController: NSObject, ObservableObject {
    enum State: Equatable {
        case off
        case installing
        /// macOS is waiting for the user in System Settings.
        case needsApproval
        case on
        case failed(String)
    }

    @Published private(set) var state: State = .off
    @Published private(set) var rules: [NetworkRule] = []
    @Published private(set) var sightings: [NetworkSighting] = []

    var programs: [NetworkProgram] { NetworkProgram.group(sightings, rules: rules) }
    private var connection: NSXPCConnection?
    private var watcher: Timer?

    static let rulesKey = "networkRules"
    private let log = Logger(subsystem: "com.antonshakirov.minimo", category: "network")
    private var extensionID: String { (Bundle.main.bundleIdentifier ?? "com.antonshakirov.minimo") + ".netfilter" }

    override init() {
        super.init()
        rules = NetworkRules.decode(UserDefaults.standard.data(forKey: Self.rulesKey))
        guard !Snapshot.active else { loadDemo(); return }
        Task { await readSystemState() }
        // SPEC: docs/spec.md — "A module that is off is off everywhere".
        NotificationCenter.default.addObserver(
            forName: ModuleActivation.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.wantsOn, !ModuleActivation.isOn("network") else { return }
                self.switchOff()
            }
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Staged programs for the design and marketing renders.
    private func loadDemo() {
        let now = Date()
        func seen(_ app: String, _ path: String, _ host: String, _ port: String, _ count: Int, _ minutes: Double,
                  _ verdict: NetworkRule.Action = .allow) -> NetworkSighting {
            NetworkSighting(app: app, path: path, host: host, address: host, port: port, verdict: verdict,
                            count: count, last: now.addingTimeInterval(-minutes * 60))
        }
        let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
        let music = "/System/Applications/Music.app/Contents/MacOS/Music"
        let notes = "/System/Applications/Notes.app/Contents/MacOS/Notes"
        sightings = [
            seen("com.apple.Safari", safari, "github.com", "443", 42, 1),
            seen("com.apple.Safari", safari, "hop.tools", "443", 12, 3),
            seen("com.apple.Safari", safari, "fonts.gstatic.com", "443", 7, 9),
            seen("com.apple.Music", music, "license.example.com", "443", 3, 14, .deny),
            seen("com.apple.Music", music, "api.example.com", "443", 20, 14),
            seen("com.apple.Notes", notes, "telemetry.example.net", "443", 9, 40, .deny),
            seen("com.apple.curl", "/usr/bin/curl", "example.com", "80", 2, 55),
        ]
        rules = [NetworkRule(app: "com.apple.Music", host: "license.example.com", action: .deny),
                 NetworkRule(app: "com.apple.Notes", action: .deny)]
        state = .on
    }

    /// The system remembers a filter across launches; the row should too.
    private func readSystemState() async {
        let manager = NEFilterManager.shared()
        guard (try? await manager.loadFromPreferences()) != nil else { return }
        if manager.isEnabled, manager.providerConfiguration?.filterDataProviderBundleIdentifier == extensionID {
            state = .on
        }
    }

    // MARK: rules

    func setProgram(_ app: String, allowed: Bool) {
        var next = rules.filter { !($0.app == app && $0.host == nil) }
        if !allowed { next.append(NetworkRule(app: app, action: .deny)) }
        setRules(next)
    }

    /// nil takes the destination's own rule away, so it follows the program again.
    func setDestination(_ app: String, _ host: String, action: NetworkRule.Action?) {
        let normalized = NetworkRule(app: app, host: host, action: .allow).host
        var next = rules.filter { !($0.app == app && $0.host == normalized) }
        if let action { next.append(NetworkRule(app: app, host: host, action: action)) }
        setRules(next)
    }

    func removeRule(_ rule: NetworkRule) {
        setRules(rules.filter { $0 != rule })
    }

    /// What a connection from `app` to `host` gets right now.
    func verdict(_ app: String, _ host: String) -> NetworkRule.Action {
        NetworkRules.verdict(for: NetworkFlow(apps: [app], hostname: host, address: host), rules: rules)
    }

    // MARK: what the filter saw

    /// Asked only while the window is open: nothing polls in the background.
    func watch() {
        guard watcher == nil, !Snapshot.active else { return }
        fetch()
        watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetch() }
        }
    }

    func unwatch() {
        watcher?.invalidate()
        watcher = nil
        connection?.invalidate()
        connection = nil
    }

    private func fetch() {
        guard state == .on, let service = service() else { return }
        service.sightings { [weak self] data in
            let list = NetworkSightings.decode(data)
            Task { @MainActor in self?.sightings = list }
        }
    }

    private var machServiceName: String? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/SystemExtensions/\(extensionID).systemextension")
        let info = Bundle(url: url)?.infoDictionary?["NetworkExtension"] as? [String: Any]
        return info?["NEMachServiceName"] as? String
    }

    private func service() -> NetworkFilterXPC? {
        if connection == nil, let name = machServiceName {
            let connection = NSXPCConnection(machServiceName: name, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: NetworkFilterXPC.self)
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            connection.resume()
            self.connection = connection
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.log.error("filter service: \(error.localizedDescription, privacy: .public)") }
        } as? NetworkFilterXPC
    }

    func switchOn() {
        guard !Snapshot.active, state != .installing else { return }
        state = .installing
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionID, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func switchOff() {
        Task { await configure(enabled: false) }
    }

    func setRules(_ next: [NetworkRule]) {
        rules = next
        guard !Snapshot.active else { return }
        UserDefaults.standard.set(NetworkRules.encode(next), forKey: Self.rulesKey)
        guard state == .on else { return }
        Task { await configure(enabled: true) }
    }

    private func configure(enabled: Bool) async {
        let manager = NEFilterManager.shared()
        do {
            try await manager.loadFromPreferences()
            let configuration = NEFilterProviderConfiguration()
            configuration.filterSockets = true
            configuration.filterPackets = false
            configuration.filterDataProviderBundleIdentifier = extensionID
            configuration.vendorConfiguration = [NetworkRules.configurationKey: NetworkRules.encode(rules)]
            manager.providerConfiguration = configuration
            manager.localizedDescription = "Hop"
            manager.isEnabled = enabled
            try await manager.saveToPreferences()
            state = enabled ? .on : .off
            log.info("filter \(enabled ? "on" : "off", privacy: .public), \(self.rules.count) rules")
        } catch {
            state = .failed(error.localizedDescription)
            log.error("filter configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension NetworkFilterController: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest,
                             actionForReplacingExtension existing: OSSystemExtensionProperties,
                             withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Task { @MainActor in
            state = .needsApproval
            log.info("extension waits for approval in System Settings")
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Task { @MainActor in
            log.info("extension request finished: \(result.rawValue, privacy: .public)")
            await configure(enabled: true)
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Task { @MainActor in
            state = .failed(error.localizedDescription)
            log.error("extension request failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
