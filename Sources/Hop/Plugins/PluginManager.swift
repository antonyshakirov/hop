import Foundation
import Combine
import HopCore
import HopPluginAPI

@MainActor
final class PluginManager: ObservableObject {
    struct Session {
        let id = UUID()
        let generation = UUID()
        let digest: String
        var theme: PluginTheme?
        var panel: PluginPanel?
    }
    struct PanelContribution {
        let owner: String
        let generation: UUID
        let panel: PluginPanel
    }
    @Published private(set) var records: [PluginRecord] = []
    @Published private(set) var catalog: [PluginCatalog.Entry] = []
    @Published private(set) var active: Set<String> = []
    @Published private(set) var panel: PanelContribution?
    @Published private(set) var busy = false
    @Published var error: String?
    private(set) var store: PluginStore?
    private let transport: PluginRuntimeTransport
    private let engine: TimerEngine
    private let system: () -> PluginValue
    private let changed: (Bool) -> Void
    private var sessions: [String: Session] = [:]
    private var pending: Task<Void, Never>?
    private var paused = false
    private var booted = false
    private var executingID: String?
    private var executingDigest: String?
    private var blockedDigests: Set<String> = []

    init(engine: TimerEngine, directory: URL, transport: PluginRuntimeTransport, system: @escaping () -> PluginValue = { .object([:]) }, changed: @escaping (Bool) -> Void = { _ in }) {
        self.engine = engine; self.transport = transport; self.system = system; self.changed = changed
        do { store = try PluginStore(directory: directory); records = store?.state.records ?? []; blockedDigests = store?.state.revoked ?? [] }
        catch { self.error = PluginError.storageFailure.rawValue }
        transport.didStop = { [weak self] reason in
            guard let self else { return }
            // XPC interruption may precede the native exit status. Preserve that
            // status after the first notification has already revoked sessions.
            let enrichingFailure = self.paused && self.error == PluginError.runtimeStopped.rawValue
                && (reason == .memoryLimit || reason == .deadlineExceeded)
            guard !self.sessions.isEmpty || self.executingID != nil || enrichingFailure else { return }
            if reason == .runtimeUnavailable { self.unavailable() }
            else { self.failRuntime(culprit: self.executingID, digest: self.executingDigest, reason: reason) }
        }
    }
    func start() {
        guard !booted else { return }
        booted = true
        for record in records where record.canRun { activate(record) }
    }
    func approve(_ id: String, digest: String, capabilities: Set<String>) {
        perform {
            guard let store else { throw PluginError.storageFailure }
            guard !blockedDigests.contains(digest) else { throw PluginError.revoked }
            try store.approve(id, digest: digest, capabilities: capabilities)
            paused = false; error = nil; publish()
            if let record = store.record(id) { activate(record) }
        }
    }
    func disable(_ id: String) {
        unload(id)
        perform { try store?.disable(id) }
        publish()
    }
    func remove(_ id: String) {
        unload(id)
        perform { try store?.remove(id) }
        publish()
    }
    func disableAll() {
        for id in Array(sessions.keys) { unload(id) }
        active.removeAll(); paused = true
        perform {
            for record in records { try store?.disable(record.id) }
        }
        publish()
    }
    func shutdown() {
        paused = true; sessions.removeAll(); active.removeAll(); transport.stop()
    }
    func setting(_ id: String, key: String, value: PluginValue) {
        perform {
            try store?.setting(id, key: key, value: value)
            unload(id); publish()
            if let record = store?.record(id), record.canRun { activate(record) }
        }
    }
    func install(_ data: Data, origin: String) {
        perform {
            guard let store else { throw PluginError.storageFailure }
            let package = try PluginPackage.decode(data)
            let old = store.record(package.manifest.id)?.digest
            let record = try store.install(data, origin: origin)
            error = nil
            if old != record.digest { unload(record.id) }
            publish()
        }
    }
    func timerFinished() {
        let event: PluginValue = .object(["type": .string("timer.finished"), "startedByPlugin": .bool(engine.startedByPlugin != nil),
                                         "session": .string(engine.controlSession.uuidString), "revision": .number(Double(engine.controlRevision))])
        for record in records where record.canRun && record.grantedCapabilities.contains("timer.read") {
            enqueue(record.id, operation: "event", event: event)
        }
    }
    func action(_ owner: String, generation: UUID, action: String) {
        guard sessions[owner]?.generation == generation else { return }
        enqueue(owner, operation: "action", action: action)
    }
    private func activate(_ record: PluginRecord) {
        guard !paused, record.canRun, !blockedDigests.contains(record.digest), sessions[record.id] == nil else { return }
        sessions[record.id] = Session(digest: record.digest)
        enqueue(record.id, operation: "activate")
    }
    private func enqueue(_ id: String, operation: String, event: PluginValue? = nil, action: String? = nil) {
        guard let session = sessions[id] else { return }
        let queuedRevision = engine.controlRevision
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            guard let self, !paused, sessions[id]?.generation == session.generation,
                  let record = store?.record(id), record.canRun, !blockedDigests.contains(record.digest), record.digest == session.digest else { return }
            guard operation == "activate" || engine.controlRevision == queuedRevision else { return }
            let revision = engine.controlRevision
            let envelope = PluginRuntimeRequest(operation: operation, session: session.id, generation: session.generation,
                                                request: UUID(), digest: record.digest, code: operation == "activate" ? record.package.code : nil,
                                                context: context(record), event: event, action: action)
            do {
                executingID = id
                executingDigest = record.digest
                defer { executingID = nil; executingDigest = nil }
                let reply = try await transport.send(envelope)
                guard !paused, sessions[id]?.generation == session.generation, store?.record(id)?.canRun == true,
                      store?.record(id)?.digest == record.digest, reply.generation == envelope.generation,
                      reply.request == envelope.request, reply.digest == envelope.digest else { return }
                guard reply.error == nil, let data = reply.result else { throw PluginError.javascriptError }
                let patch = try PluginContributions.decode(data, capabilities: record.grantedCapabilities)
                guard patch.commands.isEmpty || engine.controlRevision == revision else {
                    active.insert(id)
                    publish()
                    return
                }
                apply(patch, owner: id)
            } catch {
                if error as? PluginError == .runtimeUnavailable {
                    if sessions[id]?.generation == session.generation { unavailable() }
                }
                else if let reason = error as? PluginError, [.runtimeStopped, .memoryLimit, .deadlineExceeded].contains(reason) { failRuntime(culprit: id, digest: record.digest, reason: reason) }
                else if sessions[id]?.generation == session.generation, error as? PluginError != .staleSession {
                    failPlugin(id, reason: (error as? PluginError)?.rawValue ?? PluginError.invalidContribution.rawValue)
                }
            }
        }
    }
    private func context(_ record: PluginRecord) -> PluginValue {
        var value: [String: PluginValue] = ["settings": .object(record.settings)]
        if record.grantedCapabilities.contains("timer.read") {
            value["timer"] = .object(["state": .string(String(describing: engine.state)), "remaining": .number(engine.remaining),
                "duration": .number(engine.duration), "session": .string(engine.controlSession.uuidString),
                "revision": .number(Double(engine.controlRevision)), "startedByPlugin": .bool(engine.startedByPlugin != nil)])
        }
        if record.grantedCapabilities.contains("system.read") { value["system"] = system() }
        return .object(value)
    }
    private func apply(_ patch: PluginContributions, owner: String) {
        guard var session = sessions[owner] else { return }
        switch patch.theme { case .unchanged: break; case .clear: session.theme = nil; case .value(let v): session.theme = v }
        switch patch.panel { case .unchanged: break; case .clear: session.panel = nil; case .value(let v): session.panel = v }
        sessions[owner] = session
        active.insert(owner)
        for command in patch.commands {
            if command.type == "timer.start", let seconds = command.seconds { engine.startPluginTimer(seconds: seconds, owner: owner) }
            else if command.type == "timer.stop" { engine.reset() }
        }
        publish()
    }
    private func unload(_ id: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        active.remove(id)
        let request = PluginRuntimeRequest(operation: "unload", session: session.id, generation: session.generation, request: UUID(), digest: session.digest)
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            _ = try? await transport.send(request)
        }
    }
    private func failPlugin(_ id: String, reason: String) {
        perform { try store?.quarantine(id, reason: reason) }
        unload(id); publish()
    }
    private func unavailable() {
        paused = true; sessions.removeAll(); active.removeAll()
        error = PluginError.runtimeUnavailable.rawValue
        publish()
    }
    private func failRuntime(culprit: String?, digest: String? = nil, reason: PluginError = .runtimeStopped) {
        if paused {
            if reason == .memoryLimit || reason == .deadlineExceeded { error = reason.rawValue }
            return
        }
        let affected: [String]
        if let culprit { affected = store?.record(culprit)?.digest == (digest ?? sessions[culprit]?.digest) ? [culprit] : [] }
        else { affected = sessions.keys.filter { store?.record($0)?.digest == sessions[$0]?.digest } }
        paused = true; sessions.removeAll(); active.removeAll(); transport.stop()
        perform { for id in affected { try store?.quarantine(id, reason: reason.rawValue) } }
        error = reason.rawValue
        publish()
    }
    private func publish() {
        records = store?.state.records ?? records
        let ordered = records.compactMap { r in sessions[r.id].map { (r.id, $0) } }
        let nextTheme = ordered.compactMap { $0.1.theme }.last
        let themeChanged = Theme.pluginOverlay != nextTheme
        Theme.pluginOverlay = nextTheme
        panel = ordered.compactMap { owner, session in session.panel.map { PanelContribution(owner: owner, generation: session.generation, panel: $0) } }.last
        changed(themeChanged); objectWillChange.send()
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = (error as? PluginError)?.rawValue ?? PluginError.storageFailure.rawValue }
    }
    func refreshCatalog() async {
        guard !busy, let store else { return }
        busy = true; defer { busy = false }
        do {
            let bytes = try await Self.download(URL(string: Self.catalogURL)!, maximum: 1_048_576)
            let rawSignature = try await Self.download(URL(string: Self.catalogURL + ".sig")!, maximum: 1024)
            guard let signature = Data(base64Encoded: String(decoding: rawSignature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
                  let key = Data(base64Encoded: Self.catalogKey) else { throw PluginError.invalidSignature }
            let verified = try PluginCatalog.verified(bytes, signature: signature, publicKey: key, minimumRevision: store.state.catalogRevision)
            blockedDigests.formUnion(verified.revokedSha256)
            for record in records where blockedDigests.contains(record.digest) { unload(record.id) }
            try store.acceptCatalog(verified, digest: PluginPackage.digest(bytes))
            for record in records where store.record(record.id)?.canRun != true { unload(record.id) }
            catalog = verified.plugins; error = nil
        } catch { self.error = (error as? PluginError)?.rawValue ?? "downloadFailed" }
        publish()
    }
    func installCatalog(_ entry: PluginCatalog.Entry) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let data = try await Self.download(entry.packageURL, maximum: 1_048_576)
            try entry.verify(data)
            install(data, origin: entry.packageURL.absoluteString)
        } catch { self.error = (error as? PluginError)?.rawValue ?? "downloadFailed" }
    }
    private static let catalogURL = "https://raw.githubusercontent.com/antonyshakirov/hop-plugins/main/catalog.json"
    private static let catalogKey = "TpLZ6YZRcZbQS22vxqN6eqMW3qqkQI+BMELhylk8UYc="
    private static func download(_ url: URL, maximum: Int) async throws -> Data {
        guard url.scheme == "https" else { throw PluginError.invalidPackage }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false; config.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= maximum else { throw PluginError.invalidPackage }
        var data = Data()
        for try await byte in stream {
            guard data.count < maximum else { throw PluginError.invalidPackage }
            data.append(byte)
        }
        return data
    }
}
