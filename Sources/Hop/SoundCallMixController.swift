import AppKit
import AVFoundation
import Combine
import HopCore
import HopAudioEngine
import OSLog

struct SoundCallConfiguration: Equatable {
    var inputs: [SoundInputConfiguration]
    var apps: [SoundApplicationConfiguration]
    var input: SoundInputConfiguration? { inputs.first }
    init(input: SoundInputConfiguration?, apps: [SoundApplicationConfiguration]) {
        inputs = input.map { [$0] } ?? []; self.apps = apps
    }
    init(inputs: [SoundInputConfiguration], apps: [SoundApplicationConfiguration]) {
        self.inputs = inputs; self.apps = apps
    }
}

@MainActor
protocol SoundCallSession: AnyObject {
    var microphoneMuteChanged: ((Bool) -> Void)? { get set }
    func setMicrophoneMuted(_ value: Bool) -> Bool
    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void)
    func update(_ configuration: SoundCallConfiguration)
    func update(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void)
    func stop()
    func stop(completed: @escaping (Result<Void, SoundFailure>) -> Void)
    func shutdown()
}

extension SoundCallSession {
    func stop(completed: @escaping (Result<Void, SoundFailure>) -> Void) { stop(); completed(.success(())) }
    func update(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
        update(configuration); completed(.success(()))
    }
}

@MainActor
final class SoundCallMixController: ObservableObject {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")
    static let deviceName = "Hop Mix"
    let enabled: Bool
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var stopping = false
    @Published private(set) var failure: SoundFailure?
    static let preferencesKey = "soundCallMixPreferencesV1"
    static let sourceListKey = "soundInputSourceListV1"
    @Published private(set) var sourceList = SoundInputSourceListPreferences()
    @Published private(set) var microphone = SoundChannelSettings()
    @Published private(set) var microphones: [String: SoundChannelSettings] = [:]
    @Published private(set) var accessoryMuted = false
    @Published private(set) var updating = false
    @Published private(set) var configurationRevision = 0
    @Published private(set) var appliedConfigurationRevision = 0
    @Published private(set) var effectiveInputUIDs: [String] = []
    @Published private(set) var effectiveApplicationIDs: [String] = []
    @Published private(set) var requestingMicrophone = false
    @Published private(set) var applications: [String: SoundChannelSettings] = [:]
    var prepareInputSources: ((String?) -> Result<[SoundMixerChannel], SoundFailure>)?
    var finishInputPreparation: (() -> Void)?
    private var windowOpen = false
    private var quickInput = false
    private var captureAllowed: Bool { windowOpen || quickInput }
    private var generation = 0
    var sessionGeneration: Int { generation }
    private var requestedConfiguration: SoundCallConfiguration?
    private var inputUID: String?
    var systemInputUID: String? { inputUID }
    private var availableInputUIDs: Set<String>?
    private var microphonePermissionGranted = false
    private var microphonePermissionDenied = false
    private var sourceNames: [SoundInputSourceID: String] = [:]
    private var sources: [SoundMixerChannel] = []
    private let session: SoundCallSession
    private let access: (@escaping (Bool) -> Void) -> Void
    private let defaults: UserDefaults?

    init(enabled: Bool? = nil, session: SoundCallSession? = nil,
         access: ((@escaping (Bool) -> Void) -> Void)? = nil, defaults: UserDefaults? = nil) {
        self.defaults = defaults
        sourceList = SoundInputSourceListPreferences.load(defaults?.data(forKey: Self.sourceListKey))
        let preset = SoundInputMixPreferences.load(defaults?.data(forKey: Self.preferencesKey))
        microphone = preset.system; microphones = preset.microphones; applications = preset.applications
        if let enabled { self.enabled = enabled }
        else if #available(macOS 14.2, *) { self.enabled = true }
        else { self.enabled = false }
        if let session { self.session = session }
        else if #available(macOS 14.2, *) { self.session = NativeSoundCallSession() }
        else { self.session = UnavailableSoundCallSession() }
        self.access = access ?? { completion in
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { completion(true) }
            else { AVCaptureDevice.requestAccess(for: .audio) { allowed in DispatchQueue.main.async { completion(allowed) } } }
        }
        self.session.microphoneMuteChanged = { [weak self] value in
            guard let self, (self.running || self.starting) else { return }
            self.accessoryMuted = value
        }
    }
    func open() { windowOpen = true }
    func close() { windowOpen = false; stop() }
    func settings(_ id: String) -> SoundChannelSettings {
        if let settings = applications[id] { return settings }
        var settings = SoundChannelSettings(); settings.active = false; return settings
    }
    func microphoneSettings(uid: String) -> SoundChannelSettings {
        microphones[uid] ?? Self.inactiveSettings()
    }
    func sourceSelected(_ source: SoundInputSourceID) -> Bool {
        switch source {
        case .device(let uid): return microphoneSettings(uid: uid).active
        case .application(let id): return settings(id).active
        }
    }
    func setSourcePinned(_ value: Bool, source: SoundInputSourceID, name: String) {
        var next = sourceList
        next.remember(name, source: source); next.setPinned(value, source: source)
        saveSourceList(next)
    }
    @discardableResult func setSourceHidden(_ value: Bool, source: SoundInputSourceID, name: String) -> Bool {
        var next = sourceList
        guard next.setHidden(value, source: source, selected: sourceSelected(source)) else { return false }
        next.remember(name, source: source); saveSourceList(next)
        return true
    }
    private func saveSourceList(_ value: SoundInputSourceListPreferences) {
        guard value != sourceList else { return }
        sourceList = value
        if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: Self.sourceListKey) }
    }
    private func rememberConfiguredSourceNames() {
        let configured = Set(sourceList.names.keys).union(sourceList.pinned).union(sourceList.hidden)
            .union(microphones.keys.map(SoundInputSourceID.device))
            .union(applications.keys.map(SoundInputSourceID.application))
        var next = sourceList
        for source in configured {
            if let name = sourceNames[source] { next.remember(name, source: source) }
        }
        saveSourceList(next)
    }
    func editMicrophone(_ edit: (inout SoundChannelSettings) -> Void) {
        editMicrophone(uid: nil, edit)
    }
    func editMicrophone(uid: String?, _ edit: (inout SoundChannelSettings) -> Void) {
        guard !starting, !requestingMicrophone else { return }
        if let uid, !SoundInputMixPreferences.allowsMicrophone(uid) { return }
        let previous = uid.flatMap { microphones[$0] } ?? (uid == nil ? microphone : Self.inactiveSettings())
        var value = previous; edit(&value)
        value.gain = min(1, value.safeGain); value.bass = false
        if let uid { microphones[uid] = value } else { microphone = value }
        if let uid, value.active { _ = setSourceHidden(false, source: .device(uid), name: sourceList.names[.device(uid)] ?? uid) }
        if value.active && !previous.active { microphonePermissionDenied = false }
        rememberConfiguredSourceNames()
        persist(); sendUpdate()
    }
    func editApplication(_ id: String, _ edit: (inout SoundChannelSettings) -> Void) {
        guard SoundCallMixPolicy.allows(id), !starting else { return }
        var value = settings(id); edit(&value)
        guard !value.active || sources.filter({ $0.id != id && settings($0.id).active }).count < 4 else { return }
        value.gain = min(1, value.safeGain); value.bass = false
        applications[id] = value
        rememberConfiguredSourceNames()
        persist(); sendUpdate()
        if value.active { _ = setSourceHidden(false, source: .application(id), name: sourceList.names[.application(id)] ?? id) }
    }
    func sourcesChanged(_ apps: [SoundMixerChannel]) {
        sources = apps.filter { SoundCallMixPolicy.allows($0.id) }
        for app in sources where app.name != app.id { sourceNames[.application(app.id)] = app.name }
        rememberConfiguredSourceNames()
        sendUpdate()
    }
    func startQuick(inputUID: String?, apps: [SoundMixerChannel]) {
        guard enabled, !running, !starting, !stopping else { return }
        quickInput = true
        start(inputUID: inputUID, apps: apps)
        if !running, !starting { quickInput = false }
    }
    func start(inputUID: String?, apps initialApps: [SoundMixerChannel]) {
        guard enabled, captureAllowed, !running, !starting, !stopping else { return }
        defer { finishInputPreparation?() }
        let apps: [SoundMixerChannel]
        if let prepareInputSources {
            switch prepareInputSources(inputUID) {
            case .success(let fresh): apps = fresh
            case .failure(let error): failure = error; return
            }
        } else { apps = initialApps }
        let selected = apps.filter { SoundCallMixPolicy.allows($0.id) && settings($0.id).active }
        guard selected.count <= 4 else { failure = .unsupported; return }
        self.inputUID = inputUID; sources = apps.filter { SoundCallMixPolicy.allows($0.id) }
        generation += 1; let token = generation
        let includeMicrophone = !configuration().inputs.isEmpty
        microphonePermissionGranted = false; microphonePermissionDenied = false
        failure = nil; starting = true; requestingMicrophone = includeMicrophone
        let activate: (Bool) -> Void = { [weak self] allowed in
            guard let self, self.generation == token, self.captureAllowed, self.starting else { return }
            self.requestingMicrophone = false
            guard allowed else {
                self.quickInput = false
                self.starting = false; self.failure = .permission
                return
            }
            self.microphonePermissionGranted = includeMicrophone
            self.configurationRevision += 1
            let revision = self.configurationRevision, configuration = self.configuration()
            self.requestedConfiguration = configuration
            self.session.start(configuration) { [weak self] result in
                guard let self, self.generation == token, self.captureAllowed else { return }
                switch result {
                case .success:
                    self.running = true; self.starting = false
                    if self.configurationRevision == revision {
                        self.appliedConfigurationRevision = revision
                        self.effectiveInputUIDs = configuration.inputs.map(\.uid)
                        self.effectiveApplicationIDs = configuration.apps.map(\.id)
                    }
                case .failure(let error):
                    self.starting = false; self.quickInput = false
                    self.stop(); self.failure = error
                }
            }
        }
        if includeMicrophone { access(activate) } else { activate(true) }
    }
    func inputChanged(_ uid: String?) {
        guard inputUID != uid else { return }
        inputUID = uid
        sendUpdate()
    }
    func inputsChanged(defaultUID: String?, devices: [SoundDevice]) {
        for device in devices where device.name != device.uid { sourceNames[.device(device.uid)] = device.name }
        rememberConfiguredSourceNames()
        availableInputUIDs = Set(devices.map(\.uid).filter(SoundInputMixPreferences.allowsMicrophone))
        inputUID = defaultUID
        sendUpdate()
    }
    func stop() { stopConfirmed(completed: { _ in }) }
    func stopConfirmed(completed: @escaping (Result<Void, SoundFailure>) -> Void) {
        quickInput = false
        generation += 1; let token = generation
        stopping = true; running = false; starting = false; requestingMicrophone = false; updating = false
        requestedConfiguration = nil; inputUID = nil; sources = []
        microphonePermissionGranted = false; microphonePermissionDenied = false
        session.stop { [weak self] result in
            if let self, self.generation == token {
                self.stopping = false; self.accessoryMuted = false
                self.effectiveInputUIDs = []; self.effectiveApplicationIDs = []
                if case .failure(let error) = result { self.failure = error }
                else if self.failure == .inputRemoval { self.failure = nil }
            }
            completed(result)
        }
    }
    func shutdown() { close(); session.shutdown() }
    func stageDemo(_ apps: [SoundMixerChannel]) {
        guard Snapshot.active else { return }
        running = true; sources = apps
        if let app = apps.first { var value = SoundChannelSettings(); value.active = true; value.gain = 0.35; applications[app.id] = value }
    }
    private func configuration() -> SoundCallConfiguration {
        var preset = SoundInputMixPreferences(); preset.system = microphone; preset.microphones = microphones
        return SoundCallConfiguration(inputs: preset.resolvedInputs(defaultUID: inputUID,
            availableUIDs: availableInputUIDs ?? Set(inputUID.map { [$0] } ?? [])),
            apps: sources.filter { settings($0.id).active && !$0.processes.isEmpty }.map { SoundApplicationConfiguration(id: $0.id, processes: $0.processes, settings: settings($0.id)) })
    }
    private func sendUpdate() {
        guard (running || starting), !requestingMicrophone else { return }
        var configuration = configuration()
        if configuration.inputs.isEmpty, failure == .permission { failure = nil }
        if !configuration.inputs.isEmpty && !microphonePermissionGranted {
            if !microphonePermissionDenied {
                let token = generation
                requestingMicrophone = true
                access { [weak self] allowed in
                    guard let self, self.generation == token, self.captureAllowed, self.running || self.starting else { return }
                    self.requestingMicrophone = false
                    self.microphonePermissionGranted = allowed; self.microphonePermissionDenied = !allowed
                    self.failure = allowed ? nil : .permission
                    self.sendUpdate()
                }
                return
            }
            failure = .permission
            configuration.inputs = []
        }
        guard configuration != requestedConfiguration else { return }
        requestedConfiguration = configuration
        configurationRevision += 1
        let revision = configurationRevision, token = generation
        updating = true
        session.update(configuration) { [weak self] result in
            guard let self, self.generation == token, self.configurationRevision == revision,
                  self.captureAllowed, self.running || self.starting else { return }
            self.updating = false
            switch result {
            case .success:
                self.appliedConfigurationRevision = revision
                self.effectiveInputUIDs = configuration.inputs.map(\.uid)
                self.effectiveApplicationIDs = configuration.apps.map(\.id)
            case .failure(let error): self.stop(); self.failure = error
            }
        }
    }
    private static func inactiveSettings() -> SoundChannelSettings {
        var value = SoundChannelSettings(); value.active = false; return value
    }
    private func persist() {
        var preset = SoundInputMixPreferences()
        preset.system = microphone; preset.microphones = microphones; preset.applications = applications
        if let data = try? JSONEncoder().encode(preset) { defaults?.set(data, forKey: Self.preferencesKey) }
    }
}

@available(macOS 14.2, *)
@MainActor
final class NativeSoundCallSession: SoundCallSession {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")
    var microphoneMuteChanged: ((Bool) -> Void)?
    private var muteRelay: SoundAccessoryMuteRelay?
    private var captureToken: UUID?
    private var routeToken: UUID?
    private var microphoneUIDs: Set<String> = []
    private var microphoneMuted = false
    func setMicrophoneMuted(_ value: Bool) -> Bool {
        guard captureToken != nil, routeToken == captureToken else { return false }
        return SoundAccessoryMute.shared.setMuted(value)
    }
    private func retireMuteRoute() {
        muteRelay?.select(nil)
        if let token = routeToken { SoundAccessoryMute.shared.unbind(token) }
        routeToken = nil; captureToken = nil; microphoneUIDs = []
    }
    private func bindMuteRoute() throws {
        guard let token = captureToken, routeToken != token, let relay = muteRelay else { return }
        try SoundAccessoryMute.shared.bind(token, muted: microphoneMuted, apply: { value in
            relay.request(value, token: token.uuidString)
        }, changed: { [weak self] value in
            Task { @MainActor in
                guard let self, self.captureToken == token else { return }
                let current = SoundAccessoryMute.shared.gate.muted
                self.microphoneMuted = current; self.microphoneMuteChanged?(current)
            }
        })
        routeToken = token
    }
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var stopExport: (() throws -> Void)?
    private let makeProducer: () -> Process
    private let publishInput: (pid_t) throws -> (() throws -> Void)
    private let installAccessory: () throws -> Void
    private var pending: SoundCallConfiguration?
    private var completed: ((Result<Void, SoundFailure>) -> Void)?
    private var updateCompleted: ((Result<Void, SoundFailure>) -> Void)?
    private var stopCallbacks: [(Result<Void, SoundFailure>) -> Void] = []
    private var awaitingStop = false
    private var request: UInt64 = 0
    private var awaiting: UInt64?
    private var ready = false
    private var unavailable = false
    private var awaitingStart = false
    private var producerGeneration = 0
    private var buffer = Data()
    private var timeout: Task<Void, Never>?
    private var acknowledgement: Task<Void, Never>?

    init(makeProducer: (() -> Process)? = nil,
         publishInput: ((pid_t) throws -> (() throws -> Void))? = nil,
         installAccessory: (() throws -> Void)? = nil) {
        self.makeProducer = makeProducer ?? {
            let process = Process()
            process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HopAudioWorker.app/Contents/MacOS/HopAudioWorker")
            return process
        }
        self.publishInput = publishInput ?? { pid in
            guard let source = SoundHAL.process(pid) else { throw SoundFailure.missingDevice }
            let export = try SoundProcessTap(processes: [source], name: SoundCallMixController.deviceName, publicInput: true)
            return { try export.releaseChecked() }
        }
        self.installAccessory = installAccessory ?? { try SoundAccessoryMute.shared.install() }
    }

    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
        guard !awaitingStop else { completed(.failure(.unsupported)); return }
        Self.log.notice("start-requested")
        if unavailable {
            // An explicit retry starts from a fully reaped producer. Its old
            // public input must not keep pointing at the retired process.
            stopProducer()
            if case .failure(let error) = retireInput() { completed(.failure(error)); return }
            unavailable = false
            Self.log.notice("retry-after-failure")
        }
        do { try installAccessory() } catch {
            logError("accessory-registration", error)
            completed(.failure(.system(-1))); return
        }
        pending = configuration; self.completed = completed; awaitingStart = true
        if ready {
            guard publishInputIfNeeded() else { return }
            send(configuration); return
        }
        if process != nil { fail("producer-already-starting"); return }
        let process = makeProducer()
        guard let url = process.executableURL, FileManager.default.isExecutableFile(atPath: url.path) else { fail("missing-producer"); return }
        let commands = Pipe(), events = Pipe()
        process.standardInput = commands; process.standardOutput = events
        process.standardError = FileHandle.nullDevice
        producerGeneration += 1; let generation = producerGeneration
        self.process = process; input = commands.fileHandleForWriting; output = events.fileHandleForReading
        let relay = SoundAccessoryMuteRelay { try commands.fileHandleForWriting.write(contentsOf: $0) }
        muteRelay = relay
        output?.readabilityHandler = { [weak self] file in
            let data = file.availableData
            if data.isEmpty { relay.select(nil) } else { relay.consume(data) }
            Task { @MainActor in
                guard let self, self.producerGeneration == generation else { return }
                self.read(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.producerGeneration == generation else { return }
                self.fail("producer-exited")
            }
        }
        do { try process.run() } catch { logError("producer-launch", error); fail("producer-launch"); return }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.producerGeneration == generation, !self.ready else { return }
            self.fail("producer-ready-timeout")
        }
    }
    func update(_ configuration: SoundCallConfiguration) { update(configuration, completed: { _ in }) }
    func update(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
        guard !unavailable, !awaitingStop, (ready && stopExport != nil) || awaitingStart else { completed(.failure(.system(-1))); return }
        let previous = updateCompleted
        updateCompleted = completed
        previous?(.failure(.system(-1)))
        if ready { send(configuration) } else { pending = configuration }
    }
    func stop() { stop(completed: { _ in }) }
    func stop(completed: @escaping (Result<Void, SoundFailure>) -> Void) {
        stopCallbacks.append(completed)
        if awaitingStop { return }
        let cancellingStart = awaitingStart
        let cancellingConfiguration = awaitingStart || awaiting != nil
        Self.log.notice("stop-requested starting=\(cancellingStart, privacy: .public)")
        retireMuteRoute(); microphoneMuted = false
        pending = nil; self.completed = nil; awaiting = nil; awaitingStart = false
        let cancelled = updateCompleted; updateCompleted = nil
        cancelled?(.failure(.system(-1)))
        if cancellingConfiguration {
            stopProducer()
            unavailable = true
            finishStops()
        } else if ready {
            awaitingStop = true
            send(SoundCallConfiguration(input: nil, apps: []), stopping: true)
        } else {
            if process != nil { stopProducer(); unavailable = true }
            finishStops()
        }
    }
    private func finishStops() {
        let result = retireInput()
        if case .failure = result { stopProducer(); unavailable = true }
        awaitingStop = false
        let callbacks = stopCallbacks; stopCallbacks = []
        callbacks.forEach { $0(result) }
    }
    func shutdown() {
        stop(); stopProducer(); finishStops()
    }
    private func retireInput() -> Result<Void, SoundFailure> {
        guard let retire = stopExport else { return .success(()) }
        do {
            try retire(); stopExport = nil
            return .success(())
        } catch { logError("virtual-input-removal", error); return .failure(.inputRemoval) }
    }
    private func stopProducer() {
        producerGeneration += 1; awaitingStart = false; awaiting = nil
        retireMuteRoute()
        ready = false
        timeout?.cancel(); timeout = nil
        acknowledgement?.cancel(); acknowledgement = nil
        process?.terminationHandler = nil
        output?.readabilityHandler = nil
        try? input?.close(); input = nil
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning, Date() < deadline { usleep(10000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        process = nil; output = nil; muteRelay = nil; microphoneMuted = false
        updateCompleted = nil
        buffer.removeAll()
    }
    private func read(_ data: Data) {
        guard !unavailable else { return }
        guard !data.isEmpty, buffer.count + data.count < 65536 else { fail("producer-stream-closed"); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { fail("invalid-producer-message"); return }
            if message["ready"] as? Bool == true { publish() }
            if message["failed"] as? Bool == true {
                if message["reason"] as? String == "output-configuration-changed" {
                    Self.log.error("producer-output-configuration-changed")
                }
                if let domain = message["errorDomain"] as? String, let code = message["errorCode"] as? Int {
                    Self.log.error("producer-error domain=\(domain, privacy: .public) code=\(code)")
                }
                print("HOP CALL MIX failed: \(String((message["reason"] as? String ?? "worker failure").prefix(256)))"); fflush(stdout)
                fail("producer-reported-failure"); return
            }
            if let muted = message["microphoneMuted"] as? Bool,
               let token = captureToken, message["captureToken"] as? String == token.uuidString {
                SoundAccessoryMute.shared.gate.confirm(token, muted: muted)
                try? SoundAccessoryMute.shared.publish(muted)
                microphoneMuted = muted; microphoneMuteChanged?(muted)
            }
            if let applied = message["applied"] as? UInt64, applied == awaiting {
                do { try bindMuteRoute() } catch { logError("accessory-route", error); fail("accessory-route"); return }
                if awaitingStop, message["captureCount"] as? Int != 0 {
                    fail("stop-capture-count"); return
                }
                awaiting = nil
                acknowledgement?.cancel(); acknowledgement = nil
                if awaitingStop { finishStops(); continue }
                print("HOP CALL MIX applied=\(applied) captures=\(message["captureCount"] ?? "?")"); fflush(stdout)
                if awaitingStart {
                    awaitingStart = false
                    Self.log.notice("configuration-applied")
                    completed?(.success(()))
                }
                let updated = updateCompleted; updateCompleted = nil
                updated?(.success(()))
            }
        }
    }
    private func publish() {
        guard !unavailable, !ready, let process, process.isRunning else { fail("producer-not-running"); return }
        guard publishInputIfNeeded() else { return }
        ready = true; timeout?.cancel(); timeout = nil
        print("HOP CALL MIX ready helper=\(process.processIdentifier)"); fflush(stdout)
        if let pending { self.pending = nil; send(pending) }
    }
    private func publishInputIfNeeded() -> Bool {
        guard stopExport == nil else { return true }
        guard let process, process.isRunning else { fail("producer-not-running"); return false }
        do {
            stopExport = try publishInput(process.processIdentifier)
            Self.log.notice("virtual-input-ready")
            return true
        } catch { logError("virtual-input-creation", error); fail("virtual-input-creation"); return false }
    }
    private func send(_ configuration: SoundCallConfiguration, stopping: Bool = false) {
        guard ready, process?.isRunning == true, input != nil else { fail("producer-not-ready"); return }
        request += 1; awaiting = request
        if awaitingStart || stopping {
            Self.log.notice("configuration-requested stopping=\(stopping, privacy: .public)")
        }
        let selectedUIDs = Set(configuration.inputs.map(\.uid))
        if selectedUIDs != microphoneUIDs {
            let retainedMute = microphoneMuted
            retireMuteRoute()
            microphoneUIDs = selectedUIDs
            captureToken = selectedUIDs.isEmpty ? nil : UUID()
            microphoneMuted = retainedMute
            muteRelay?.select(captureToken?.uuidString)
        }
        let command = SoundWorkerCommand(start: true, inputs: configuration.inputs, apps: configuration.apps, requestID: request, captureToken: captureToken?.uuidString, microphoneMuted: microphoneMuted)
        do {
            var data = try JSONEncoder().encode(command); data.append(10)
            guard let muteRelay else { fail("missing-command-relay"); return }
            try muteRelay.send(data)
            acknowledgement?.cancel()
            let token = request
            acknowledgement = Task { [weak self] in
                try? await Task.sleep(for: .seconds(stopping ? 1 : 8))
                guard !Task.isCancelled, let self, self.awaiting == token else { return }
                self.fail(stopping ? "stop-acknowledgement-timeout" : "configuration-acknowledgement-timeout")
                print("HOP CALL MIX producer terminated: missing acknowledgement"); fflush(stdout)
            }
        } catch { logError("producer-command", error); fail("producer-command") }
    }
    private func logError(_ stage: String, _ error: Error) {
        if let failure = error as? SoundFailure, case .system(let status) = failure {
            Self.log.error("stage=\(stage, privacy: .public) OSStatus=\(status)")
            return
        }
        let error = error as NSError
        Self.log.error("stage=\(stage, privacy: .public) domain=\(error.domain, privacy: .public) code=\(error.code)")
    }
    private func fail(_ reason: String) {
        Self.log.error("failed phase=\(reason, privacy: .public)")
        pending = nil; awaiting = nil; unavailable = true
        let callback = completed; completed = nil
        let updated = updateCompleted; updateCompleted = nil
        stopProducer(); finishStops()
        callback?(.failure(.system(-1)))
        updated?(.failure(.system(-1)))
    }
}

@MainActor
private final class UnavailableSoundCallSession: SoundCallSession {
    var microphoneMuteChanged: ((Bool) -> Void)?
    func setMicrophoneMuted(_ value: Bool) -> Bool { false }
    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { completed(.failure(.unsupported)) }
    func update(_ configuration: SoundCallConfiguration) {}
    func stop() {}
    func shutdown() {}
}
