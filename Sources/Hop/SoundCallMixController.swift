import AppKit
import AVFoundation
import Combine
import HopCore
import HopAudioEngine

struct SoundCallConfiguration {
    var input: SoundInputConfiguration?
    var apps: [SoundApplicationConfiguration]
}

@MainActor
protocol SoundCallSession: AnyObject {
    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void)
    func update(_ configuration: SoundCallConfiguration)
    func stop()
    func shutdown()
}

@MainActor
final class SoundCallMixController: ObservableObject {
    static let deviceName = "Hop Mix"
    let enabled: Bool
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var failure: SoundFailure?
    @Published private(set) var microphone: SoundChannelSettings = { var value = SoundChannelSettings(); value.active = false; return value }()
    @Published private(set) var requestingMicrophone = false
    @Published private(set) var applications: [String: SoundChannelSettings] = [:]
    private var windowOpen = false
    private var generation = 0
    private var inputUID: String?
    private var sources: [SoundMixerChannel] = []
    private let session: SoundCallSession
    private let access: (@escaping (Bool) -> Void) -> Void

    init(enabled: Bool = CommandLine.arguments.contains("--zoom-mix-prototype")
            || (Bundle.isDevBuild && Bundle.main.object(forInfoDictionaryKey: "HopZoomMixPrototype") as? Bool == true), session: SoundCallSession? = nil,
         access: ((@escaping (Bool) -> Void) -> Void)? = nil) {
        self.enabled = enabled
        if let session { self.session = session }
        else if #available(macOS 14.2, *) { self.session = NativeSoundCallSession() }
        else { self.session = UnavailableSoundCallSession() }
        self.access = access ?? { completion in
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { completion(true) }
            else { AVCaptureDevice.requestAccess(for: .audio) { allowed in DispatchQueue.main.async { completion(allowed) } } }
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
                guard let self, self.generation == token, self.windowOpen, self.running, self.inputUID == inputUID else { return }
                self.requestingMicrophone = false
                guard allowed else { self.failure = .permission; return }
                self.failure = nil; self.microphone = value; self.sendUpdate()
            }
        } else { microphone = value; sendUpdate() }
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
    func start(inputUID: String?, apps: [SoundMixerChannel]) {
        guard enabled, windowOpen, !running, !starting else { return }
        let selected = apps.filter { SoundCallMixPolicy.allows($0.id) && settings($0.id).active }
        guard selected.count <= 4, !microphone.active || inputUID != nil else { failure = .missingDevice; return }
        self.inputUID = inputUID; sources = apps.filter { SoundCallMixPolicy.allows($0.id) }
        generation += 1; let token = generation
        failure = nil; starting = true
        let activate: (Bool) -> Void = { [weak self] allowed in
            guard let self, self.generation == token, self.windowOpen, self.starting else { return }
            guard allowed else { self.starting = false; self.failure = .permission; return }
            self.session.start(self.configuration()) { [weak self] result in
                guard let self, self.generation == token, self.windowOpen else { return }
                self.starting = false
                switch result {
                case .success: self.running = true
                case .failure(let error): self.running = false; self.failure = error; self.session.stop()
                }
            }
        }
        if microphone.active { access(activate) } else { activate(true) }
    }
    func inputChanged(_ uid: String?) {
        if running || starting {
            if (microphone.active || requestingMicrophone), uid != inputUID { stop(); failure = .inputChanged }
            else { inputUID = uid }
        }
    }
    func stop() {
        generation += 1; running = false; starting = false; requestingMicrophone = false
        session.stop(); inputUID = nil; sources = []
        microphone.active = false
        applications = applications.mapValues { old in var value = old; value.active = false; return value }
    }
    func shutdown() { close(); session.shutdown() }
    private func configuration() -> SoundCallConfiguration {
        SoundCallConfiguration(input: microphone.active ? inputUID.map { SoundInputConfiguration(uid: $0, settings: microphone) } : nil,
            apps: sources.filter { settings($0.id).active }.map { SoundApplicationConfiguration(id: $0.id, processes: $0.processes, settings: settings($0.id)) })
    }
    private func sendUpdate() { if running { session.update(configuration()) } }
}

@available(macOS 14.2, *)
@MainActor
private final class NativeSoundCallSession: SoundCallSession {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var export: SoundProcessTap?
    private var pending: SoundCallConfiguration?
    private var completed: ((Result<Void, SoundFailure>) -> Void)?
    private var request: UInt64 = 0
    private var awaiting: UInt64?
    private var ready = false
    private var unavailable = false
    private var buffer = Data()
    private var timeout: Task<Void, Never>?
    private var acknowledgement: Task<Void, Never>?

    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) {
        guard !unavailable else { completed(.failure(.system(-1))); return }
        pending = configuration; self.completed = completed
        if ready { send(configuration); return }
        if process != nil { fail(); return }
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HopAudioWorker.app/Contents/MacOS/HopAudioWorker")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { fail(); return }
        let process = Process(), commands = Pipe(), events = Pipe()
        process.executableURL = url; process.standardInput = commands; process.standardOutput = events
        process.standardError = FileHandle.nullDevice
        self.process = process; input = commands.fileHandleForWriting; output = events.fileHandleForReading
        output?.readabilityHandler = { [weak self] file in
            let data = file.availableData
            Task { @MainActor in self?.read(data) }
        }
        process.terminationHandler = { [weak self] _ in Task { @MainActor in self?.fail() } }
        do { try process.run() } catch { fail(); return }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, !self.ready else { return }
            self.fail()
        }
    }
    func update(_ configuration: SoundCallConfiguration) { if ready { send(configuration) } }
    func stop() {
        pending = nil; completed = nil; awaiting = nil
        if ready { send(SoundCallConfiguration(input: nil, apps: []), stopping: true) }
    }
    func shutdown() {
        stop(); stopProducer()
        export?.stop(); export = nil
    }
    private func stopProducer() {
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
        process = nil; output = nil
        buffer.removeAll()
    }
    private func read(_ data: Data) {
        guard !unavailable else { return }
        guard !data.isEmpty, buffer.count + data.count < 65536 else { fail(); return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { fail(); return }
            if message["ready"] as? Bool == true { publish() }
            if message["failed"] as? Bool == true {
                print("HOP CALL MIX failed: \(String((message["reason"] as? String ?? "worker failure").prefix(256)))"); fflush(stdout)
                fail(); return
            }
            if let applied = message["applied"] as? UInt64, applied == awaiting {
                awaiting = nil
                acknowledgement?.cancel(); acknowledgement = nil
                print("HOP CALL MIX applied=\(applied) captures=\(message["captureCount"] ?? "?")"); fflush(stdout)
                completed?(.success(()))
            }
        }
    }
    private func publish() {
        guard !unavailable, !ready, let process, process.isRunning else { fail(); return }
        guard let source = SoundHAL.process(process.processIdentifier) else { fail(); return }
        do {
            export = try SoundProcessTap(processes: [source], name: SoundCallMixController.deviceName, publicInput: true)
            ready = true; timeout?.cancel(); timeout = nil
            print("HOP CALL MIX ready helper=\(process.processIdentifier)"); fflush(stdout)
            if let pending { self.pending = nil; send(pending) }
        } catch { fail() }
    }
    private func send(_ configuration: SoundCallConfiguration, stopping: Bool = false) {
        guard ready, process?.isRunning == true, let input else { fail(); return }
        request += 1; awaiting = request
        let command = SoundWorkerCommand(start: true, inputs: configuration.input.map { [$0] } ?? [], apps: configuration.apps, requestID: request)
        do {
            var data = try JSONEncoder().encode(command); data.append(10)
            try input.write(contentsOf: data)
            acknowledgement?.cancel()
            let token = request
            acknowledgement = Task { [weak self] in
                try? await Task.sleep(for: .seconds(stopping ? 1 : 8))
                guard !Task.isCancelled, let self, self.awaiting == token else { return }
                self.fail()
                print("HOP CALL MIX producer terminated: missing acknowledgement"); fflush(stdout)
            }
        } catch { fail() }
    }
    private func fail() {
        pending = nil; awaiting = nil; unavailable = true
        let callback = completed; completed = nil
        // A failed command cannot leave a previous capture running. Keep the
        // published input until quit, but reap its producer before reporting failure.
        stopProducer()
        callback?(.failure(.system(-1)))
    }
}

@MainActor
private final class UnavailableSoundCallSession: SoundCallSession {
    func start(_ configuration: SoundCallConfiguration, completed: @escaping (Result<Void, SoundFailure>) -> Void) { completed(.failure(.unsupported)) }
    func update(_ configuration: SoundCallConfiguration) {}
    func stop() {}
    func shutdown() {}
}
