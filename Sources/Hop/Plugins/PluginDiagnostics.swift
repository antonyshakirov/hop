import Foundation
import HopCore
import HopPluginAPI
import Darwin

@MainActor
enum PluginDiagnostics {
    private static var directory: URL?
    private static var stageName = "preflight"
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--plugin-runtime-check") || args.contains("--plugin-restore-check") else { return }
        guard Bundle.main.bundleIdentifier == "com.antonshakirov.minimo.dev", args.count == 4 else {
            print("plugin runtime guard: development identity or argument count"); exit(1)
        }
        let environment = ProcessInfo.processInfo.environment
        guard let path = physical(args[2]), path.hasPrefix("/private/tmp/hop-plugin-proof-"),
              let fixedHome = environment["CFFIXED_USER_HOME"], physical(fixedHome) == path + "/home",
              let home = environment["HOME"], physical(home) == path + "/home",
              let temporary = environment["TMPDIR"], physical(temporary) == path + "/tmp"
        else { print("plugin runtime guard: private physical paths"); exit(1) }
        for directory in [path, path + "/home", path + "/tmp"] {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory),
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0 else { exit(1) }
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        directory = output
        Task {
            do {
                let result = args.contains("--plugin-restore-check") ? try await restore(output: output) : try await run(output: output, fixtures: URL(fileURLWithPath: args[3]))
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                    .write(to: output.appendingPathComponent(args.contains("--plugin-restore-check") ? "restore-proof.json" : "runtime-proof.json"))
                print("plugin runtime: PASS")
                exit(0)
            } catch {
                print("plugin runtime: FAIL \(error)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }
    private static func wait(_ condition: @escaping () -> Bool, seconds: Double = 5) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard condition() else { throw PluginError.runtimeStopped }
    }
    private static func physical(_ path: String) -> String? {
        guard let buffer = realpath(path, nil) else { return nil }
        defer { free(buffer) }
        return String(cString: buffer)
    }
    private static func checkpoint(_ name: String, manager: PluginManager, client: PluginRuntimeClient) {
        stageName = name
        let value: [String: Any] = ["stage": name, "parentPID": getpid(), "runtimePID": Int(client.processIdentifier ?? 0),
            "waitStatus": client.lastWaitStatus ?? -1, "requests": client.sentRequests, "completed": client.completedRequests,
            "managerError": manager.error ?? "", "transportError": client.lastTransportError ?? [:],
            "active": manager.active.sorted()]
        if let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
            FileHandle.standardOutput.write(bytes + Data([10]))
            if let directory { try? bytes.write(to: directory.appendingPathComponent("last-stage.json")) }
        }
    }
    private static func restore(output: URL) async throws -> [String: Any] {
        let engine = TimerEngine(), client = PluginRuntimeClient()
        let manager = PluginManager(engine: engine, directory: output.appendingPathComponent("store"), transport: client)
        defer { checkpoint("restore-exit", manager: manager, client: client); manager.shutdown() }
        checkpoint("restore-start", manager: manager, client: client)
        try require(manager.records.first(where: { $0.id == "desk-panel" })?.settings["accent"] == .string("#4466cc"), "settings persisted across parent restart")
        manager.start()
        try await wait { manager.active.contains("desk-panel") }
        try require(manager.panel?.panel.width == 420 && Theme.pluginOverlay?.light?["accent"] == "#4466cc", "wanted plugin restored")
        let pid = Int(client.processIdentifier ?? 0)
        manager.disableAll()
        return ["status": "PASS", "parentPID": getpid(), "runtimePID": pid, "settingsAndWantedSurviveParentRestart": true]
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "HopPluginProof", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    private static func package(_ id: String, capabilities: [String], code: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["formatVersion": 1, "manifest": ["id": id, "version": "1.0.0", "apiVersion": 1,
            "name": id, "description": "Local isolation probe", "author": "Hop", "capabilities": capabilities, "settings": []], "code": code])
    }
    private static func run(output: URL, fixtures: URL) async throws -> [String: Any] {
        var observations: [String: Any] = [:]
        var beats = 0
        let heartbeat = DispatchSource.makeTimerSource(queue: .main)
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(50))
        heartbeat.setEventHandler { beats += 1 }; heartbeat.resume()
        defer { heartbeat.cancel() }
        var moment = Date()
        let timer = TimerEngine(now: { moment })
        let client = PluginRuntimeClient()
        let manager = PluginManager(engine: timer, directory: output.appendingPathComponent("store"), transport: client)
        defer { checkpoint("exit-after-" + stageName, manager: manager, client: client); manager.shutdown(); timer.onFinish = nil; timer.reset() }
        let desk = try Data(contentsOf: fixtures.appendingPathComponent("desk-panel-1.0.0.hopplugin"))
        let auto = try Data(contentsOf: fixtures.appendingPathComponent("auto-break-1.0.0.hopplugin"))
        manager.install(desk, origin: "local"); manager.install(auto, origin: "local"); manager.start()
        checkpoint("default-off", manager: manager, client: client)
        try require(client.processIdentifier == nil && client.sentRequests == 0 && manager.active.isEmpty, "all-off startup")
        observations["defaultOff"] = ["runtimePID": NSNull(), "runtimeRequests": 0]
        for id in ["desk-panel", "auto-break"] { manager.remove(id) }
        checkpoint("catalog-fetch", manager: manager, client: client)
        await manager.refreshCatalog()
        try require(manager.catalog.count == 2 && manager.error == nil, "live signed catalog")
        for entry in manager.catalog { await manager.installCatalog(entry) }
        try require(manager.records.count == 2 && manager.records.allSatisfy({ !$0.wantedEnabled }) && client.sentRequests == 0, "catalog installs stay off")
        observations["catalog"] = ["verifiedEntries": manager.catalog.count, "revision": manager.store?.state.catalogRevision ?? -1, "explicitFetch": true, "runtimeRequestsAfterInstall": client.sentRequests]
        func enable(_ id: String) throws {
            guard let record = manager.records.first(where: { $0.id == id }) else { throw PluginError.invalidPackage }
            manager.approve(id, digest: record.digest, capabilities: Set(record.package.manifest.capabilities))
        }
        try enable("desk-panel")
        checkpoint("desk-enable", manager: manager, client: client)
        try await wait { manager.active.contains("desk-panel") }
        try require(manager.panel?.panel.width == 420 && Theme.pluginOverlay != nil, "desk contributions")
        let originalPeer = try unwrap(client.processIdentifier)
        let completedBeforeSetting = client.completedRequests
        manager.setting("desk-panel", key: "accent", value: .string("#4466cc"))
        checkpoint("desk-setting-reload", manager: manager, client: client)
        try await wait { manager.active.contains("desk-panel") && client.completedRequests > completedBeforeSetting }
        try require(client.processIdentifier == originalPeer, "reload reuses shared runtime after unloading old generation")
        try require(Theme.pluginOverlay?.light?["accent"] == "#4466cc", "setting reload")
        for _ in 0..<3 {
            manager.disable("desk-panel")
            try enable("desk-panel")
            try await wait { manager.active.contains("desk-panel") }
        }
        observations["deskAndReload"] = ["firstPID": originalPeer, "lastPID": Int(client.processIdentifier ?? 0),
                                          "width": 420, "accent": "#4466cc", "rapidToggleCycles": 3]
        let restored = try PluginStore(directory: output.appendingPathComponent("store"))
        try require(restored.record("desk-panel")?.settings["accent"] == .string("#4466cc") && restored.record("desk-panel")?.canRun == true, "persisted settings and wanted selection")
        let secondClient = client
        let crashPID = try unwrap(secondClient.processIdentifier)
        checkpoint("idle-crash", manager: manager, client: client)
        kill(crashPID, SIGKILL)
        try await wait { manager.active.isEmpty && manager.panel == nil && Theme.pluginOverlay == nil }
        try await wait { secondClient.lastWaitStatus != nil }
        observations["idleCrash"] = ["pid": crashPID, "waitStatus": secondClient.lastWaitStatus ?? -1, "coreRestored": true]
        manager.disable("desk-panel")
        try enable("auto-break")
        checkpoint("explicit-retry-under-launchd-throttle", manager: manager, client: client)
        try await wait { manager.error == PluginError.runtimeUnavailable.rawValue || manager.active.contains("auto-break") }
        try require(manager.records.first(where: { $0.id == "auto-break" })?.quarantinedDigest == nil, "availability does not quarantine innocent plugin")
        if !manager.active.contains("auto-break") {
            try await Task.sleep(nanoseconds: 12_000_000_000)
            try enable("auto-break")
        }
        try await wait { manager.active.contains("auto-break") }
        checkpoint("auto-break", manager: manager, client: client)
        var finishes = 0
        timer.onFinish = { finishes += 1; manager.timerFinished() }
        timer.setDuration(1); timer.start(); moment.addTimeInterval(2); timer.tick()
        try await wait { timer.state == .running && timer.startedByPlugin == "auto-break" }
        let breakSeconds = timer.duration
        let completedBeforeOwn = secondClient.completedRequests
        moment.addTimeInterval(breakSeconds + 1); timer.tick()
        try await wait { secondClient.completedRequests > completedBeforeOwn }
        try require(timer.state == .finished && finishes == 2, "own break completion must not loop")
        observations["autoBreak"] = ["seconds": breakSeconds, "nativeFinishes": finishes, "ownCompletionSkipped": true]
        manager.disable("auto-break"); timer.onFinish = nil; timer.reset()
        let raceCode = "definePlugin({onEvent(e){var end=Date.now()+40;while(Date.now()<end){};return {commands:[{type:'timer.start',seconds:60}]};}})"
        manager.install(try package("manual-race", capabilities: ["timer.read", "timer.control"], code: raceCode), origin: "local")
        checkpoint("manual-revision-race", manager: manager, client: client)
        try enable("manual-race"); try await wait { manager.active.contains("manual-race") }
        timer.onFinish = { manager.timerFinished() }
        let sentBeforeRace = secondClient.sentRequests, completedBeforeRace = secondClient.completedRequests
        timer.setDuration(1); timer.start(); moment.addTimeInterval(2); timer.tick()
        try await wait { secondClient.sentRequests > sentBeforeRace }
        timer.setPreset(minutes: 9)
        try await wait { secondClient.completedRequests > completedBeforeRace }
        try require(timer.state == .idle && timer.duration == 540, "manual timer change wins")
        observations["manualRevisionWins"] = true
        manager.disable("manual-race"); timer.onFinish = nil
        manager.install(try package("deadline-probe", capabilities: [], code: "while(true){}"), origin: "local")
        checkpoint("deadline", manager: manager, client: client)
        let beatsBefore = beats
        try enable("deadline-probe")
        try await wait { manager.records.first(where: { $0.id == "deadline-probe" })?.quarantinedDigest != nil }
        try await wait { secondClient.lastWaitStatus == 124 << 8 }
        try require(beats - beatsBefore >= 5 && manager.panel == nil, "deadline parent responsive")
        observations["deadline"] = ["waitStatus": secondClient.lastWaitStatus ?? -1, "heartbeats": beats - beatsBefore]
        manager.disable("deadline-probe")
        try await Task.sleep(nanoseconds: 12_000_000_000)
        let memoryCode = "var retained=[];definePlugin({activate(){return {panel:{mode:'replace',nodes:[{type:'button',title:'Allocate',action:'allocate'}]}}},onAction(){retained.push(new Uint8Array(16*1024*1024).fill(1));return {};}})"
        manager.install(try package("memory-probe", capabilities: ["ui.panel"], code: memoryCode), origin: "local")
        checkpoint("memory", manager: manager, client: client)
        try enable("memory-probe"); try await wait { manager.active.contains("memory-probe") }
        for _ in 0..<12 where manager.active.contains("memory-probe") {
            let previous = secondClient.completedRequests
            if let panel = manager.panel { manager.action(panel.owner, generation: panel.generation, action: "allocate") }
            try await wait { secondClient.completedRequests > previous || manager.active.isEmpty }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        try await wait { manager.error == PluginError.memoryLimit.rawValue }
        try require(manager.panel == nil && Theme.pluginOverlay == nil && secondClient.lastWaitStatus == 125 << 8, "memory limit core recovery")
        observations["memory"] = ["waitStatus": secondClient.lastWaitStatus ?? -1, "limitMiB": 128, "maximumAttemptedAllocationMiB": 192, "coreRestored": true]
        let requestsAfterFailure = secondClient.sentRequests
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try require(secondClient.sentRequests == requestsAfterFailure && secondClient.processIdentifier == nil, "no restart loop")
        observations["noAutomaticRetrySeconds"] = 2
        if let desk = manager.store?.record("desk-panel") {
            try manager.store?.approve(desk.id, digest: desk.digest, capabilities: Set(desk.package.manifest.capabilities))
        }
        checkpoint("complete-pending-parent-restart", manager: manager, client: client)
        observations["parentPID"] = getpid()
        observations["status"] = "PASS"
        return observations
    }
    private static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw PluginError.runtimeStopped }
        return value
    }
}
