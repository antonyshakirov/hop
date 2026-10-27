import AppKit
import AVFoundation
import Combine
import HopCore
import HopAudioEngine
import OSLog

struct SoundCallConfiguration {
    var input: SoundInputConfiguration?
    var apps: [SoundApplicationConfiguration]
}

@MainActor
protocol SoundCallSession: AnyObject {
    var microphoneMuteChanged: ((Bool) -> Void)? { get set }
    func setMicrophoneMuted(_ value: Bool) -> Bool
    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void)
    func update(_ configuration: SoundCallConfiguration)
    func stop()
    func shutdown()
}

@MainActor
final class SoundCallMixController: ObservableObject {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")
    static let deviceName = "Hop Mix"
    let enabled: Bool
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var failure: SoundFailure?
    @Published private(set) var microphone: SoundChannelSettings = { var value = SoundChannelSettings(); value.active = false; return value }()
    @Published private(set) var requestingMicrophone = false
    @Published private(set) var applications: [String: SoundChannelSettings] = [:]
    var prepareInputSources: ((String?) -> Result<[SoundMixerChannel], SoundFailure>)?
    var finishInputPreparation: (() -> Void)?
    private var windowOpen = false
    private var quickInput = false
    private var captureAllowed: Bool { windowOpen || quickInput }
    private var generation = 0
    private var inputUID: String?
    private var sources: [SoundMixerChannel] = []
    private let session: SoundCallSession
    private let access: (@escaping (Bool) -> Void) -> Void

    init(enabled: Bool? = nil, session: SoundCallSession? = nil,
         access: ((@escaping (Bool) -> Void) -> Void)? = nil) {
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
            guard let self, (self.running || self.starting), self.microphone.active else { return }
            self.microphone.muted = value
        }
    }
    func open() { windowOpen = true }
    func close() { windowOpen = false; stop() }
    func settings(_ id: String) -> SoundChannelSettings {
        if let settings = applications[id] { return settings }
        var settings = SoundChannelSettings(); settings.active = false; return settings
    }
    func editMicrophone(_ edit: (inout SoundChannelSettings) -> Void) {
        guard !starting, !requestingMicrophone else { return }
        var value = microphone; edit(&value)
        value.gain = min(1, value.safeGain); value.bass = false
        if running, value.active, !microphone.active {
            guard let inputUID else { failure = .missingDevice; return }
            let token = generation
            requestingMicrophone = true
            access { [weak self] allowed in
                guard let self, self.generation == token, self.captureAllowed, self.running, self.inputUID == inputUID else { return }
                self.requestingMicrophone = false
                guard allowed else { self.failure = .permission; return }
                self.failure = nil; self.microphone = value; self.sendUpdate()
            }
        } else {
            if running, microphone.active, value.active, value.muted != microphone.muted,
               !session.setMicrophoneMuted(value.muted) { failure = .system(-1); return }
            microphone = value; sendUpdate()
        }
    }
    func editApplication(_ id: String, _ edit: (inout SoundChannelSettings) -> Void) {
        guard SoundCallMixPolicy.allows(id), !starting else { return }
        var value = settings(id); edit(&value)
        guard !value.active || sources.filter({ $0.id != id && settings($0.id).active }).count < 4 else { return }
        value.gain = min(1, value.safeGain); value.bass = false
        applications[id] = value; sendUpdate()
    }
    func sourcesChanged(_ apps: [SoundMixerChannel]) {
        sources = apps.filter { SoundCallMixPolicy.allows($0.id) }
        sendUpdate()
    }
    func startQuick(inputUID: String?, apps: [SoundMixerChannel]) {
        guard enabled, !running, !starting else { return }
        guard inputUID != nil else { failure = .missingDevice; return }
        quickInput = true
        start(inputUID: inputUID, apps: apps)
        if !running, !starting { quickInput = false }
    }
    func start(inputUID: String?, apps initialApps: [SoundMixerChannel]) {
        guard enabled, captureAllowed, !running, !starting else { return }
        defer { finishInputPreparation?() }
        let apps: [SoundMixerChannel]
        if let prepareInputSources {
            switch prepareInputSources(inputUID) {
            case .success(let fresh): apps = fresh
            case .failure(let error): failure = error; return
            }
        } else { apps = initialApps }
        let selected = apps.filter { SoundCallMixPolicy.allows($0.id) && settings($0.id).active }
        guard selected.count <= 4, !microphone.active || inputUID != nil else { failure = .missingDevice; return }
        self.inputUID = inputUID; sources = apps.filter { SoundCallMixPolicy.allows($0.id) }
        generation += 1; let token = generation
        let includeMicrophone = inputUID != nil
        failure = nil; starting = true; requestingMicrophone = includeMicrophone
        let activate: (Bool) -> Void = { [weak self] allowed in
            guard let self, self.generation == token, self.captureAllowed, self.starting else { return }
            self.requestingMicrophone = false
            guard allowed else {
                self.quickInput = false
                self.starting = false; self.microphone.active = false; self.failure = .permission
                return
            }
            if includeMicrophone { self.microphone.active = true }
            self.session.start(self.configuration()) { [weak self] result in
                guard let self, self.generation == token, self.captureAllowed else { return }
                switch result {
                case .success: self.running = true; self.starting = false
                case .failure(let error):
                    self.starting = false; self.quickInput = false
                    self.running = false; self.microphone.active = false; self.failure = error; self.session.stop()
                }
            }
        }
        if includeMicrophone { access(activate) } else { activate(true) }
    }
    func inputChanged(_ uid: String?) {
        if running || starting {
            if (microphone.active || requestingMicrophone), uid != inputUID {
                Self.log.notice("selected-input-changed; stopping-capture")
                stop(); failure = .inputChanged
            }
            else { inputUID = uid }
        }
    }
    func stop() {
        quickInput = false
        generation += 1; running = false; starting = false; requestingMicrophone = false
        session.stop(); inputUID = nil; sources = []
        microphone.active = false
        applications = applications.mapValues { old in var value = old; value.active = false; return value }
    }
    func shutdown() { close(); session.shutdown() }
    func stageDemo(_ apps: [SoundMixerChannel]) {
        guard Snapshot.active else { return }
        running = true; sources = apps
        if let app = apps.first { var value = SoundChannelSettings(); value.active = true; value.gain = 0.35; applications[app.id] = value }
    }
    private func configuration() -> SoundCallConfiguration {
        SoundCallConfiguration(input: microphone.active ? inputUID.map { SoundInputConfiguration(uid: $0, settings: microphone) } : nil,
            apps: sources.filter { settings($0.id).active && !$0.processes.isEmpty }.map { SoundApplicationConfiguration(id: $0.id, processes: $0.processes, settings: settings($0.id)) })
    }
    private func sendUpdate() { if running { session.update(configuration()) } }
}

@available(macOS 14.2, *)
@MainActor
final class NativeSoundCallSession: SoundCallSession {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")
    var microphoneMuteChanged: ((Bool) -> Void)?
    private var muteRelay: SoundAccessoryMuteRelay?
    private var captureToken: UUID?
    private var routeToken: UUID?
    private var microphoneUID: String?
    private var microphoneMuted = false
    func setMicrophoneMuted(_ value: Bool) -> Bool {
        guard captureToken != nil, routeToken == captureToken else { return false }
        return SoundAccessoryMute.shared.setMuted(value)
    }
    private func retireMuteRoute() {
        muteRelay?.select(nil)
        if let token = routeToken { SoundAccessoryMute.shared.unbind(token) }
        routeToken = nil; captureToken = nil; microphoneUID = nil
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
    private var stopExport: (() -> Void)?
    private let makeProducer: () -> Process
    private let publishInput: (pid_t) throws -> (() -> Void)
    private let installAccessory: () throws -> Void
    private var pending: SoundCallConfiguration?
    private var completed: ((Result<Void, SoundFailure>) -> Void)?
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
         publishInput: ((pid_t) throws -> (() -> Void))? = nil,
         installAccessory: (() throws -> Void)? = nil) {
        self.makeProducer = makeProducer ?? {
            let process = Process()
            process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HopAudioWorker.app/Contents/MacOS/HopAudioWorker")
            return process
        }
        self.publishInput = publishInput ?? { pid in
            guard let source = SoundHAL.process(pid) else { throw SoundFailure.missingDevice }
            let export = try SoundProcessTap(processes: [source], name: SoundCallMixController.deviceName, publicInput: true)
            return { export.stop() }
        }
        self.installAccessory = installAccessory ?? { try SoundAccessoryMute.shared.install() }
    }

    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
        Self.log.notice("start-requested")
        if unavailable {
            // An explicit retry starts from a fully reaped producer. Its old
            // public input must not keep pointing at the retired process.
            stopProducer()
            stopExport?(); stopExport = nil
            unavailable = false
            Self.log.notice("retry-after-failure")
        }
        do { try installAccessory() } catch {
            logError("accessory-registration", error)
            completed(.failure(.system(-1))); return
        }
        pending = configuration; self.completed = completed; awaitingStart = true
        if ready { send(configuration); return }
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
    func update(_ configuration: SoundCallConfiguration) { if ready { send(configuration) } }
    func stop() {
        let cancellingStart = awaitingStart
        Self.log.notice("stop-requested starting=\(cancellingStart, privacy: .public)")
        retireMuteRoute()
        pending = nil; completed = nil; awaiting = nil; awaitingStart = false
        if cancellingStart {
            // The worker can be blocked opening a Bluetooth device and unable
            // to read a Stop command. Reap it before returning from cancellation.
            stopProducer()
            stopExport?(); stopExport = nil
        } else if ready { send(SoundCallConfiguration(input: nil, apps: []), stopping: true) }
    }
    func shutdown() {
        stop(); stopProducer()
        stopExport?(); stopExport = nil
    }
    private func stopProducer() {
        producerGeneration += 1; awaitingStart = false
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
        process = nil; output = nil; muteRelay = nil
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
                awaiting = nil
                acknowledgement?.cancel(); acknowledgement = nil
                print("HOP CALL MIX applied=\(applied) captures=\(message["captureCount"] ?? "?")"); fflush(stdout)
                if awaitingStart {
                    awaitingStart = false
                    Self.log.notice("configuration-applied")
                    completed?(.success(()))
                }
            }
        }
    }
    private func publish() {
        guard !unavailable, !ready, let process, process.isRunning else { fail("producer-not-running"); return }
        do {
            stopExport = try publishInput(process.processIdentifier)
            ready = true; timeout?.cancel(); timeout = nil
            print("HOP CALL MIX ready helper=\(process.processIdentifier)"); fflush(stdout)
            Self.log.notice("virtual-input-ready")
            if let pending { self.pending = nil; send(pending) }
        } catch { logError("virtual-input-creation", error); fail("virtual-input-creation") }
    }
    private func send(_ configuration: SoundCallConfiguration, stopping: Bool = false) {
        guard ready, process?.isRunning == true, input != nil else { fail("producer-not-ready"); return }
        request += 1; awaiting = request
        if awaitingStart || stopping {
            Self.log.notice("configuration-requested stopping=\(stopping, privacy: .public)")
        }
        if configuration.input?.uid != microphoneUID {
            retireMuteRoute()
            microphoneUID = configuration.input?.uid
            captureToken = configuration.input.map { _ in UUID() }
            microphoneMuted = configuration.input?.settings.muted ?? false
            muteRelay?.select(captureToken?.uuidString)
        }
        let command = SoundWorkerCommand(start: true, inputs: configuration.input.map { [$0] } ?? [], apps: configuration.apps, requestID: request, captureToken: captureToken?.uuidString)
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
        // A failed command cannot leave a previous capture running. Keep the
        // published input until explicit retry or quit, but reap its producer first.
        stopProducer()
        callback?(.failure(.system(-1)))
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
