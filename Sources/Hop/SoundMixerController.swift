import AppKit
import AVFoundation
import Combine
import CoreAudio
import HopAudioDSP
import HopCore
import HopAudioEngine

@MainActor
final class SoundMixerLevel: ObservableObject { @Published var peak: Double = 0 }

@MainActor
final class SoundMixerChannel: ObservableObject, Identifiable {
    let id: String
    let name: String
    let input: Bool
    let level = SoundMixerLevel()
    @Published var settings: SoundChannelSettings
    var processes: [AudioObjectID] = []
    init(id: String, name: String, input: Bool, settings: SoundChannelSettings) {
        self.id = id; self.name = name; self.input = input; self.settings = settings
    }
}

@MainActor
private protocol SoundMixingSession: AnyObject {
    func outputs(_ channels: [SoundMixerChannel])
    func inputs(_ channels: [SoundMixerChannel], visible: Bool, denoiseAll: Bool)
    func configure(_ channel: SoundMixerChannel)
    func levels() -> [String: Double]
    func stop()
}

@MainActor
final class SoundMixerController: ObservableObject {
    @Published private(set) var apps: [SoundMixerChannel] = []
    @Published private(set) var inputs: [SoundMixerChannel] = []
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var failure: SoundFailure?
    @Published private(set) var denoiseAll: Bool
    var available: Bool { if #available(macOS 14.2, *) { true } else { false } }
    private var visible = false
    private var observations: [SoundHALObservation] = []
    private var meters: Timer?
    private var session: SoundMixingSession?
    private var generation = 0
    private let enabled: () -> Bool
    private let defaults: UserDefaults
    private var saved: [String: SoundChannelSettings]
    private var refreshTask: Task<Void, Never>?

    init(enabled: @escaping () -> Bool = { true }, defaults: UserDefaults = .standard) {
        self.enabled = enabled; self.defaults = defaults
        denoiseAll = defaults.bool(forKey: "soundMixerDenoiseAll")
        saved = defaults.data(forKey: "soundMixerChannels").flatMap { try? JSONDecoder().decode([String: SoundChannelSettings].self, from: $0) } ?? [:]
    }
    func open() {
        guard enabled(), available else { return }
        if #available(macOS 14.2, *), !running, !Snapshot.active { SoundProcessTap.cleanStaleVirtualInput() }
        visible = true; refresh(); watch(); updateMeters()
        session?.inputs(inputs, visible: true, denoiseAll: denoiseAll)
    }
    func close() {
        visible = false; meters?.invalidate(); meters = nil
        session?.inputs(inputs, visible: false, denoiseAll: denoiseAll)
        if !running, !starting { observations.removeAll(); refreshTask?.cancel(); refreshTask = nil }
    }
    func toggleInputDenoise() {
        denoiseAll.toggle()
        defaults.set(denoiseAll, forKey: "soundMixerDenoiseAll")
        session?.inputs(inputs, visible: visible, denoiseAll: denoiseAll)
        if denoiseAll { start() } else { stopIfIdle() }
    }
    func update(_ channel: SoundMixerChannel, _ edit: (inout SoundChannelSettings) -> Void) {
        let wasDenoising = channel.settings.denoise
        edit(&channel.settings)
        channel.settings.gain = channel.settings.safeGain
        saved[(channel.input ? "input:" : "app:") + channel.id] = channel.settings
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "soundMixerChannels") }
        session?.configure(channel)
        if channel.input { session?.inputs(inputs, visible: visible, denoiseAll: denoiseAll) }
        if channel.input, channel.settings.denoise, !wasDenoising { start() }
        stopIfIdle()
    }
    private func stopIfIdle() {
        guard running || starting,
              !SoundMixerActivity.requiresProcessing(apps: apps.map(\.settings), inputs: inputs.map(\.settings), denoiseAll: denoiseAll) else { return }
        stop()
    }
    func start() {
        guard enabled(), available, !running, !starting else { return }
        refresh(); failure = nil; starting = true; generation += 1
        let token = generation
        let proceed: (Bool) -> Void = { [weak self] allowed in
            guard let self, self.generation == token, self.starting, self.enabled() else { return }
            guard allowed else { self.starting = false; self.failure = .permission; return }
            if #available(macOS 14.2, *) {
                let session = SoundRoutingSession { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.stop(); self.failure = .system(-1)
                }
                self.session = session
                self.running = true; self.starting = false; self.watch()
                session.outputs(self.apps); session.inputs(self.inputs, visible: self.visible, denoiseAll: self.denoiseAll)
                self.updateMeters()
            }
        }
        if inputs.contains(where: { $0.settings.active }) {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: proceed(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { allowed in DispatchQueue.main.async { proceed(allowed) } }
            default: proceed(false)
            }
        } else { proceed(true) }
    }
    func stop() {
        generation += 1; starting = false; running = false
        session?.stop(); session = nil; meters?.invalidate(); meters = nil
        apps.forEach { $0.level.peak = 0 }; inputs.forEach { $0.level.peak = 0 }
        if !visible { observations.removeAll(); refreshTask?.cancel(); refreshTask = nil }
    }
    private func watch() {
        observations.removeAll()
        let system = AudioObjectID(kAudioObjectSystemObject)
        let changed: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.enabled(), self.visible || self.running else { return }
                self.refreshTask?.cancel()
                self.refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self else { return }
                    self.refresh(); self.watch()
                }
            }
        }
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices] {
            if let observation = SoundHALObservation(system, selector, changed: changed) { observations.append(observation) }
        }
        if let observation = SoundHALObservation(system, kAudioHardwarePropertyDefaultOutputDevice, changed: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                self.session?.outputs([]); self.session?.outputs(self.apps)
            }
        }) { observations.append(observation) }
        for id in SoundHAL.ids(system, kAudioHardwarePropertyProcessObjectList) {
            if let observation = SoundHALObservation(id, kAudioProcessPropertyIsRunningOutput, changed: changed) { observations.append(observation) }
        }
    }
    private func refresh() {
        let runningApps = NSWorkspace.shared.runningApplications
        var groups: [String: (String, [AudioObjectID])] = [:]
        let oldApps = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let processIDs = SoundHAL.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        if #available(macOS 14.2, *) {
            for id in processIDs {
                guard SoundHAL.value(id, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1,
                      let pid = SoundHAL.value(id, kAudioProcessPropertyPID, pid_t(0)),
                      pid != ProcessInfo.processInfo.processIdentifier,
                      let app = NSRunningApplication(processIdentifier: pid),
                      let rawID = app.bundleIdentifier ?? SoundHAL.string(id, kAudioProcessPropertyBundleID),
                      !rawID.hasPrefix("com.antonshakirov.minimo"), !rawID.hasPrefix("com.antonshakirov.hop") else { continue }
                let owner = runningApps.filter { other in
                    guard let bundle = other.bundleIdentifier, !bundle.isEmpty else { return false }
                    return rawID == bundle || rawID.hasPrefix(bundle + ".")
                }.min { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) } ?? app
                let key = owner.bundleIdentifier ?? rawID
                let name = owner.localizedName ?? app.localizedName ?? key
                var group = groups[key] ?? (name, [])
                group.1.append(id); groups[key] = group
            }
        }
        if running {
            for (key, channel) in oldApps {
                let connected = channel.processes.filter { processIDs.contains($0) }
                if !connected.isEmpty {
                    let existing = groups[key]?.1 ?? []
                    groups[key] = (channel.name, Array(Set(connected + existing)))
                }
            }
        }
        var outputsChanged = Set(groups.keys) != Set(oldApps.keys)
        let nextApps = groups.map { key, value -> SoundMixerChannel in
            let channel = oldApps[key] ?? SoundMixerChannel(id: key, name: value.0, input: false, settings: saved["app:" + key] ?? .init())
            let ids = value.1.sorted()
            if channel.processes != ids { outputsChanged = true; channel.processes = ids }
            return channel
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if outputsChanged { apps = nextApps; session?.outputs(apps) }
        let hardware = CoreSoundHardware()
        let current = hardware.defaultUID(.input)
        let devices = hardware.devices(.input)
        let oldInputs = Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, $0) })
        let physical = devices.filter { !$0.uid.hasPrefix("com.antonshakirov.hop.audio.") }
        let nextInputs = physical.map { device -> SoundMixerChannel in
            var settings = saved["input:" + device.uid] ?? .init()
            if saved["input:" + device.uid] == nil { settings.active = device.uid == current }
            return oldInputs[device.uid] ?? SoundMixerChannel(id: device.uid, name: device.name, input: true, settings: settings)
        }
        if nextInputs.map(\.id) != inputs.map(\.id) { inputs = nextInputs; session?.inputs(inputs, visible: visible, denoiseAll: denoiseAll) }
    }
    private func updateMeters() {
        meters?.invalidate(); meters = nil
        guard visible, running else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let levels = self.session?.levels() ?? [:]
                for channel in self.apps {
                    let peak = levels[channel.id] ?? 0
                    if abs(channel.level.peak - peak) > 0.01 { channel.level.peak = peak }
                }
            }
        }
        meters = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stageDemo() {
        apps = [SoundMixerChannel(id: "browser", name: "YouTube · Safari", input: false, settings: .init()),
                SoundMixerChannel(id: "music", name: "Music", input: false, settings: .init())]
        apps[0].settings.gain = 0.65; apps[1].settings.gain = 0.3
        inputs = [SoundMixerChannel(id: "input", name: "MacBook Air Microphone", input: true, settings: .init())]
        inputs[0].settings.gain = 1.4; inputs[0].settings.denoise = true
    }
}

@available(macOS 14.2, *)
@MainActor
private final class SoundRoutingSession: SoundMixingSession {
    private var streams: [String: SoundOutputStream] = [:]
    private var processIDs: [String: [AudioObjectID]] = [:]
    private var build: Task<[(String, SoundOutputStream)], Error>?
    private var generation = 0
    private var workerGeneration = 0
    private var worker: Process?
    private var commands: Pipe?
    private var virtual: SoundProcessTap?
    private var latestInputs: [SoundInputConfiguration] = []
    private var visible = false
    private var inputChannels: [String: SoundMixerChannel] = [:]
    private let failed: () -> Void
    init(failed: @escaping () -> Void) { self.failed = failed }
    func outputs(_ channels: [SoundMixerChannel]) {
        generation += 1; build?.cancel(); build = nil
        let desired = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0.processes) })
        for id in Array(streams.keys) where desired[id] != processIDs[id] {
            streams.removeValue(forKey: id)?.stop(); processIDs.removeValue(forKey: id)
        }
        for channel in channels { configure(channel) }
        let missing = channels.filter { streams[$0.id] == nil }
        guard !missing.isEmpty else { return }
        let token = generation
        let descriptions = missing.map { ($0.id, $0.processes, $0.settings) }
        let streamFailed: () -> Void = { [weak self] in
            DispatchQueue.main.async { self?.failed() }
        }
        let task = Task.detached(priority: .userInitiated) {
            var built: [(String, SoundOutputStream)] = []
            do {
                for (id, processes, settings) in descriptions {
                    try Task.checkCancellation()
                    built.append((id, try SoundOutputStream(processes: processes, settings: settings, failed: streamFailed)))
                }
                try Task.checkCancellation(); return built
            } catch { built.forEach { $0.1.stop() }; throw error }
        }
        build = task
        Task { [weak self] in
            do {
                let built = try await task.value
                guard let self, self.generation == token else { built.forEach { $0.1.stop() }; return }
                for (id, stream) in built { self.streams[id] = stream; self.processIDs[id] = desired[id] }
                self.build = nil
                for channel in channels { self.configure(channel) }
            } catch is CancellationError {} catch {
                guard let self, self.generation == token else { return }
                self.build = nil; self.failed()
            }
        }
    }
    func configure(_ channel: SoundMixerChannel) {
        if !channel.input { streams[channel.id]?.channel.configure(channel.settings) }
    }
    func levels() -> [String: Double] { streams.mapValues { Double(hop_audio_peak($0.channel.pointer)) } }
    func inputs(_ channels: [SoundMixerChannel], visible: Bool, denoiseAll: Bool) {
        self.visible = visible
        latestInputs = channels.map { SoundInputConfiguration(uid: $0.id, settings: $0.settings, denoiseAll: denoiseAll) }
        inputChannels = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        guard !channels.isEmpty else { stopWorker(); return }
        if worker == nil { startWorker() } else if virtual != nil { send(start: false) }
    }
    private func startWorker() {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/HopAudioWorker.app/Contents/MacOS/HopAudioWorker")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { failed(); return }
        workerGeneration += 1
        let token = workerGeneration, process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        worker = process; commands = input
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(data, token: token) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { if self?.workerGeneration == token { self?.failed() } }
        }
        do { try process.run() } catch { failed() }
    }
    private var pending = Data()
    private func receive(_ data: Data, token: Int) {
        guard workerGeneration == token, let worker else { return }
        pending.append(data)
        guard pending.count < 65536 else { failed(); return }
        while let newline = pending.firstIndex(of: 10) {
            let line = pending.prefix(upTo: newline); pending.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if message["ready"] as? Bool == true {
                guard let process = SoundHAL.process(worker.processIdentifier) else { failed(); return }
                do { virtual = try SoundProcessTap(processes: [process], name: "Hop Input", publicInput: true); send(start: true) }
                catch { failed() }
            }
            if message["failed"] as? Bool == true { failed(); return }
            if let levels = message["levels"] as? [String: Double], visible {
                for (uid, value) in levels { if let channel = inputChannels[uid], abs(channel.level.peak - value) > 0.01 { channel.level.peak = value } }
            }
        }
    }
    private func send(start: Bool) {
        let command = SoundWorkerCommand(start: start, meters: visible, inputs: latestInputs)
        guard var data = try? JSONEncoder().encode(command) else { failed(); return }
        data.append(10)
        do { try commands?.fileHandleForWriting.write(contentsOf: data) } catch { failed() }
    }
    private func stopWorker() {
        workerGeneration += 1; pending.removeAll()
        let process = worker, tap = virtual
        worker = nil; virtual = nil
        try? commands?.fileHandleForWriting.close(); commands = nil
        if let process {
            process.terminationHandler = nil
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            withExtendedLifetime(tap) {}
        }
    }
    func stop() { generation += 1; build?.cancel(); build = nil; streams.values.forEach { $0.stop() }; streams.removeAll(); processIDs.removeAll(); stopWorker() }
}
