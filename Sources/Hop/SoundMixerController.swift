import AppKit
import Combine
import CoreAudio
import HopCore
import HopAudioEngine

@MainActor
final class SoundMixerChannel: ObservableObject, Identifiable {
    let id: String
    let name: String
    let input: Bool
    @Published var settings: SoundChannelSettings
    var processes: [AudioObjectID] = []
    init(id: String, name: String, input: Bool, settings: SoundChannelSettings) {
        self.id = id; self.name = name; self.input = input; self.settings = settings
    }
}

@MainActor
protocol SoundMixingSession: AnyObject {
    func outputs(_ channels: [SoundMixerChannel])
    func configure(_ channel: SoundMixerChannel)
    func stop()
}

@MainActor
final class SoundMixerController: ObservableObject {
    @Published private(set) var apps: [SoundMixerChannel] = []
    static let enabledKey = "soundMixerEnabled"
    @Published private(set) var requested: Bool
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var failure: SoundFailure?
    var available: Bool { if #available(macOS 14.2, *) { true } else { false } }
    private var visible = false
    private var observations: [SoundHALObservation] = []
    private var session: SoundMixingSession?
    private var generation = 0
    private let enabled: () -> Bool
    private let defaults: UserDefaults
    private let makeSession: (@escaping (SoundFailure) -> Void) -> SoundMixingSession
    private var saved: [String: SoundChannelSettings]
    private var refreshTask: Task<Void, Never>?

    init(enabled: @escaping () -> Bool = { true }, defaults: UserDefaults = .standard,
         makeSession: ((@escaping (SoundFailure) -> Void) -> SoundMixingSession)? = nil) {
        self.enabled = enabled; self.defaults = defaults
        requested = defaults.bool(forKey: Self.enabledKey)
        self.makeSession = makeSession ?? { failed in
            if #available(macOS 14.2, *) { return SoundRoutingSession(failed: failed) }
            preconditionFailure("Mixer requires macOS14.2")
        }
        defaults.removeObject(forKey: "soundMixerDenoiseAll")
        saved = defaults.data(forKey: "soundMixerChannels").flatMap { try? JSONDecoder().decode([String: SoundChannelSettings].self, from: $0) } ?? [:]
    }
    func open() {
        guard enabled(), available else { return }
        if #available(macOS 14.2, *), !running, !Snapshot.active { SoundProcessTap.cleanStaleVirtualInput() }
        visible = true; refresh(); watch()
    }
    func close() {
        visible = false
        if !running, !starting { observations.removeAll(); refreshTask?.cancel(); refreshTask = nil }
    }
    func update(_ channel: SoundMixerChannel, _ edit: (inout SoundChannelSettings) -> Void) {
        guard !channel.input else { return }
        edit(&channel.settings)
        channel.settings.gain = min(1, channel.settings.safeGain)
        channel.settings.active = true
        saved[(channel.input ? "input:" : "app:") + channel.id] = channel.settings
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "soundMixerChannels") }
        session?.configure(channel)
    }
    func resumeIfEnabled() {
        guard requested else { return }
        start()
    }
    func start() {
        guard enabled(), available, !running, !starting else { return }
        requested = true
        defaults.set(true, forKey: Self.enabledKey)
        if #available(macOS 14.2, *), !Snapshot.active { SoundProcessTap.cleanStaleVirtualInput() }
        refresh(); failure = nil; starting = true; generation += 1
        let token = generation
        let session = makeSession { [weak self] failure in
            guard let self, self.generation == token else { return }
            self.suspend(); self.failure = failure
        }
        self.session = session
        running = true; starting = false; watch()
        session.outputs(apps)
    }
    func stop() {
        requested = false
        defaults.set(false, forKey: Self.enabledKey)
        suspend()
        failure = nil
    }
    func suspend() {
        generation += 1; starting = false; running = false
        session?.stop(); session = nil
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
                      pid != ProcessInfo.processInfo.processIdentifier else { continue }
                let app = NSRunningApplication(processIdentifier: pid)
                guard let rawID = app?.bundleIdentifier ?? SoundHAL.string(id, kAudioProcessPropertyBundleID),
                      !rawID.hasPrefix("com.antonshakirov.minimo"), !rawID.hasPrefix("com.antonshakirov.hop") else { continue }
                let owner = runningApps.filter { other in
                    guard let bundle = other.bundleIdentifier, !bundle.isEmpty else { return false }
                    return rawID == bundle || rawID.hasPrefix(bundle + ".")
                }.min { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) } ?? app
                let key = owner?.bundleIdentifier ?? rawID
                let name = owner?.localizedName ?? app?.localizedName ?? key
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
            channel.settings.gain = min(1, channel.settings.safeGain)
            channel.settings.active = true
            let ids = value.1.sorted()
            if channel.processes != ids { outputsChanged = true; channel.processes = ids }
            return channel
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if outputsChanged { apps = nextApps; session?.outputs(apps) }
    }
    func stageDemo() {
        if Snapshot.active { requested = true; running = true }
        apps = [SoundMixerChannel(id: "browser", name: "Safari", input: false, settings: .init()),
                SoundMixerChannel(id: "music", name: "Music", input: false, settings: .init())]
        apps[0].settings.gain = 0.65; apps[1].settings.gain = 0.3
    }
}

@available(macOS 14.2, *)
@MainActor
private final class SoundRoutingSession: SoundMixingSession {
    private var streams: [String: SoundOutputStream] = [:]
    private var processIDs: [String: [AudioObjectID]] = [:]
    private var build: Task<[(String, SoundOutputStream)], Error>?
    private var generation = 0
    private let failed: (SoundFailure) -> Void
    init(failed: @escaping (SoundFailure) -> Void) { self.failed = failed }
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
            DispatchQueue.main.async { self?.failed(.system(-1)) }
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
                self.build = nil; self.failed(error as? SoundFailure ?? .system(-1))
            }
        }
    }
    func configure(_ channel: SoundMixerChannel) {
        if !channel.input { streams[channel.id]?.channel.configure(channel.settings) }
    }
    func stop() {
        generation += 1; build?.cancel(); build = nil
        streams.values.forEach { $0.stop() }; streams.removeAll(); processIDs.removeAll()
    }
}
