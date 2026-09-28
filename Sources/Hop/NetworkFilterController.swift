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
    /// Every app in the Applications folders, so any of them can be ruled on
    /// before it ever connects. Read when the window opens.
    @Published private(set) var installed: [(id: String, name: String)] = []

    var programs: [NetworkProgram] { NetworkProgram.group(sightings, rules: rules) }
    private var connection: NSXPCConnection?
    private var watcher: Timer?

    /// Connections waiting for an answer, oldest first.
    @Published private(set) var questions: [NetworkSighting] = []
    /// The filter process went away while on: traffic flows unchecked until it is back.
    @Published private(set) var stopped = false
    private var replies: [String: (String) -> Void] = [:]
    private let receiver = AskReceiver()

    private var asks: Bool { UserDefaults.standard.bool(forKey: SettingsKey.networkAsk) }

    static let rulesKey = "networkRules"
    private let log = Logger(subsystem: "com.antonshakirov.minimo", category: "network")
    private var extensionID: String { (Bundle.main.bundleIdentifier ?? "com.antonshakirov.minimo") + ".netfilter" }

    override init() {
        super.init()
        rules = NetworkRules.decode(UserDefaults.standard.data(forKey: Self.rulesKey))
        guard !Snapshot.active else { loadDemo(); return }
        receiver.onAsk = { [weak self] data, reply in
            Task { @MainActor in self?.receive(data, reply: reply) }
        }
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

    /// `--network-state off|approval|failed` for the renders of the setup card.
    func stageForSnapshot(_ name: String) {
        switch name {
        case "off": state = .off
        case "approval": state = .needsApproval
        case "failed": state = .failed("")
        default: break
        }
    }

    func stageQuestionForSnapshot() {
        questions = [NetworkSighting(app: "com.apple.Music", path: "/System/Applications/Music.app/Contents/MacOS/Music",
                                     host: "license.example.com", address: "203.0.113.7", port: "443",
                                     verdict: .allow, last: Date()),
                     NetworkSighting(app: "com.apple.Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari",
                                     host: "github.com", address: "140.82.121.4", port: "443",
                                     verdict: .allow, last: Date())]
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
                 NetworkRule(app: "com.apple.Notes", action: .deny),
                 NetworkRule(app: NetworkRule.anyProgram, host: "tracker.example.com", action: .deny)]
        installed = [("com.apple.Maps", "Maps"), ("com.apple.Music", "Music"), ("com.apple.Notes", "Notes"),
                     ("com.apple.Photos", "Photos"), ("com.apple.Safari", "Safari"),
                     ("com.apple.TextEdit", "TextEdit")]
        state = .on
    }

    /// The system remembers a filter across launches; the row should too.
    private func readSystemState() async {
        let manager = NEFilterManager.shared()
        guard (try? await manager.loadFromPreferences()) != nil else { return }
        if manager.isEnabled, manager.providerConfiguration?.filterDataProviderBundleIdentifier == extensionID {
            state = .on
            syncAsking()
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
        loadInstalled()
        guard watcher == nil, !Snapshot.active else { return }
        fetch()
        watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetch() }
        }
    }

    private func loadInstalled() {
        guard installed.isEmpty else { return }
        Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                           "/System/Applications/Utilities", home + "/Applications"]
            var seen = Set<String>()
            var apps: [(id: String, name: String)] = []
            for folder in folders {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
                for name in names where name.hasSuffix(".app") {
                    guard let id = Bundle(path: folder + "/" + name)?.bundleIdentifier,
                          seen.insert(id).inserted else { continue }
                    apps.append((id, String(name.dropLast(4))))
                }
            }
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let found = apps
            await MainActor.run { self.installed = found }
        }
    }

    /// Rules from a file, merged over the current ones; how many it brought.
    func importRules(from url: URL) -> Int? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let incoming = NetworkRuleFile.parse(text)
        guard !incoming.isEmpty else { return 0 }
        setRules(NetworkRuleFile.merge(rules, incoming))
        return incoming.count
    }

    func exportRules(to url: URL) -> Bool {
        (try? NetworkRuleFile.text(rules).write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    func unwatch() {
        watcher?.invalidate()
        watcher = nil
        guard state != .on else { return }
        connection?.invalidate()
        connection = nil
    }

    /// SPEC: docs/spec.md — "Network access", a stopped filter. Said once,
    /// then the row carries it until the filter answers again.
    private func filterStopped() {
        guard state == .on else { return }
        if !stopped {
            stopped = true
            if let screen = NSScreen.main?.visibleFrame {
                MarkupNote.show(L10n.t(.networkStopped, L10n.current),
                                detail: L10n.t(.networkStoppedDetail, L10n.current),
                                over: CGRect(x: screen.maxX - 200, y: screen.maxY - 2, width: 2, height: 2),
                                lasting: 8)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.probe() }
    }

    private func probe() {
        guard state == .on, stopped else { return }
        service()?.sightings { [weak self] _ in
            Task { @MainActor in
                guard let self, self.stopped else { return }
                self.stopped = false
                self.syncAsking()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.probe() }
    }

    // MARK: questions

    /// The filter asks only while this app says it will answer.
    func syncAsking() {
        guard !Snapshot.active else { return }
        if state == .on {
            service()?.setAsking(asks)
            if !asks { dropQuestions() }
        } else if let connection {
            (connection.remoteObjectProxy as? NetworkFilterXPC)?.setAsking(false)
            if watcher == nil {
                connection.invalidate()
                self.connection = nil
            }
            dropQuestions()
        }
    }

    private func receive(_ data: Data, reply: @escaping (String) -> Void) {
        guard let sighting = NetworkSightings.decode(data).first, !Snapshot.active else { return reply("") }
        let key = Self.key(sighting)
        replies[key] = reply
        questions.append(sighting)
        NetworkQuestionPanel.show(self)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.answerWait) { [weak self] in
            self?.expire(key)
        }
    }

    static let answerWait: TimeInterval = 30

    static func key(_ sighting: NetworkSighting) -> String { sighting.app + " " + sighting.destination }

    /// The answer becomes a rule, so the question is not asked again.
    func answer(_ sighting: NetworkSighting, _ action: NetworkRule.Action, wholeProgram: Bool) {
        if wholeProgram {
            setProgram(sighting.app, allowed: action == .allow)
        } else {
            setDestination(sighting.app, sighting.destination, action: action)
        }
        let answered = questions.filter { Self.key($0) == Self.key(sighting) || (wholeProgram && $0.app == sighting.app) }
        for question in answered {
            replies.removeValue(forKey: Self.key(question))?(action.rawValue)
        }
        questions.removeAll { question in answered.contains { Self.key($0) == Self.key(question) } }
        if questions.isEmpty { NetworkQuestionPanel.hide() }
    }

    private func expire(_ key: String) {
        guard let reply = replies.removeValue(forKey: key) else { return }
        reply("")
        questions.removeAll { Self.key($0) == key }
        if questions.isEmpty { NetworkQuestionPanel.hide() }
    }

    private func dropQuestions() {
        for reply in replies.values { reply("") }
        replies = [:]
        questions = []
        NetworkQuestionPanel.hide()
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
            connection.exportedInterface = NSXPCInterface(with: NetworkFilterAskerXPC.self)
            connection.exportedObject = receiver
            connection.interruptionHandler = { [weak self] in
                Task { @MainActor in
                    self?.dropQuestions()
                    self?.filterStopped()
                }
            }
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.connection = nil
                    self.dropQuestions()
                    guard self.state == .on else { return }
                    self.filterStopped()
                }
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
            syncAsking()
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

/// Receives the filter's questions on the XPC queue and hands them to the app.
private final class AskReceiver: NSObject, NetworkFilterAskerXPC, @unchecked Sendable {
    var onAsk: ((Data, @escaping (String) -> Void) -> Void)?

    func ask(_ sighting: Data, reply: @escaping (String) -> Void) {
        guard let onAsk else { return reply("") }
        onAsk(sighting, reply)
    }
}
