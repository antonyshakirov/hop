import AppKit
import Combine
import CoreAudio
import HopCore
import HopAudioEngine

@MainActor
final class SoundMixerChannel: ObservableObject, Identifiable {
    let id: String
    let input: Bool
    @Published var name: String
    @Published var settings: SoundChannelSettings
    @Published var preference: SoundAppPreference
    @Published var routeState: SoundAppRouteState = .stopped
    @Published var appRunning = true
    @Published var hasAudio = false
    @Published private(set) var icon: NSImage?
    var sourceRunning = false
    var processes: [AudioObjectID] = []
    var lastSignal: TimeInterval = 0
    private var iconURL: URL?
    init(id: String, name: String, input: Bool, settings: SoundChannelSettings) {
        self.id = id; self.name = name; self.input = input; self.settings = settings
        preference = SoundAppPreference(name: name)
        updateIcon(nil)
    }
    func updateIcon(_ url: URL?) {
        let resolved = (url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id))?.resolvingSymlinksInPath()
        guard resolved != iconURL else { return }
        iconURL = resolved
        icon = resolved.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

@MainActor
protocol SoundMixingSession: AnyObject {
    func outputs(_ channels: [SoundMixerChannel])
    func configure(_ channel: SoundMixerChannel)
    func stop()
    func sourceLevel(_ id: String) -> Float
}
extension SoundMixingSession { func sourceLevel(_ id: String) -> Float { 0 } }

@MainActor
final class SoundMixerController: ObservableObject {
    static let enabledKey = "soundMixerEnabled"
    static let preferencesKey = "soundMixerAppPreferences"
    @Published private(set) var apps: [SoundMixerChannel] = []
    @Published private(set) var sourceRevision = 0
    @Published private(set) var outputDevices: [SoundDevice] = []
    @Published private(set) var requested: Bool
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var failure: SoundFailure?
    var available: Bool { if #available(macOS 14.2, *) { true } else { false } }
    var hasCustomApplicationAudio: Bool {
        saved.contains { $0.key.hasPrefix("app:") && SoundMixerDiscovery.allowsApplication(String($0.key.dropFirst(4)))
            && (min(1, $0.value.safeGain) != 1 || $0.value.muted) }
            || preferences.contains { SoundMixerDiscovery.allowsApplication($0.key) && $0.value.outputUID != nil }
    }
    private var visible = false
    private var observingInput = false
    private var observations: [SoundHALObservation] = []
    private var session: SoundMixingSession?
    private var generation = 0
    private let enabled: () -> Bool
    private let defaults: UserDefaults
    private let makeSession: (@escaping (SoundFailure) -> Void) -> SoundMixingSession
    private let discover: () -> [SoundMixerAppSnapshot]
    private let outputs: () -> [SoundDevice]
    private let observeHardware: Bool
    private var saved: [String: SoundChannelSettings]
    private var preferences: [String: SoundAppPreference]
    private var refreshTask: Task<Void, Never>?
    private var activityTimer: Timer?

    init(enabled: @escaping () -> Bool = { true }, defaults: UserDefaults = .standard,
         makeSession: ((@escaping (SoundFailure) -> Void) -> SoundMixingSession)? = nil,
         discover: (() -> [SoundMixerAppSnapshot])? = nil, outputs: (() -> [SoundDevice])? = nil) {
        self.enabled = enabled; self.defaults = defaults
        requested = defaults.bool(forKey: Self.enabledKey)
        self.makeSession = makeSession ?? { failed in
            if #available(macOS 14.2, *) { return SoundRoutingSession(failed: failed) }
            preconditionFailure("Mixer requires macOS14.2")
        }
        self.discover = discover ?? { SoundMixerDiscovery.applications() }
        let hardware = CoreSoundHardware()
        self.outputs = outputs ?? { hardware.devices(.output) }
        observeHardware = discover == nil
        defaults.removeObject(forKey: "soundMixerDenoiseAll")
        saved = defaults.data(forKey: "soundMixerChannels").flatMap { try? JSONDecoder().decode([String: SoundChannelSettings].self, from: $0) } ?? [:]
        preferences = defaults.data(forKey: Self.preferencesKey).flatMap { try? JSONDecoder().decode([String: SoundAppPreference].self, from: $0) } ?? [:]
    }
    func open() {
        guard enabled(), available else { return }
        if #available(macOS 14.2, *), observeHardware, !running, !observingInput, !Snapshot.active { SoundProcessTap.cleanStaleVirtualInput() }
        visible = true; refresh(); watch(); updateActivityTimer()
    }
    func close() {
        visible = false; updateActivityTimer()
        if !running, !starting, !observingInput { observations.removeAll(); refreshTask?.cancel(); refreshTask = nil }
    }
    func beginInputObservation() {
        guard enabled(), available, !observingInput else { return }
        observingInput = true; refresh(); watch()
    }
    func endInputObservation() {
        observingInput = false
        if !visible, !running, !starting { observations.removeAll(); refreshTask?.cancel(); refreshTask = nil }
    }
    func update(_ channel: SoundMixerChannel, _ edit: (inout SoundChannelSettings) -> Void) {
        guard !channel.input else { return }
        objectWillChange.send()
        edit(&channel.settings)
        channel.settings.gain = min(1, channel.settings.safeGain)
        channel.settings.active = true; channel.settings.bass = false
        saved["app:" + channel.id] = channel.settings
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "soundMixerChannels") }
        session?.configure(channel)
    }
    func selectOutput(_ channel: SoundMixerChannel, uid: String?) {
        guard !channel.input else { return }
        objectWillChange.send()
        var value = preferences[channel.id] ?? SoundAppPreference(name: channel.name)
        value.outputUID = uid
        value.outputName = uid.flatMap { selected in outputDevices.first { $0.uid == selected }?.name ?? value.outputName ?? selected }
        preferences[channel.id] = value; channel.preference = value; persistPreferences()
        session?.configure(channel)
    }
    func addApplication(id: String, name: String) {
        guard SoundMixerDiscovery.allowsApplication(id) else { return }
        var value = preferences[id] ?? SoundAppPreference(name: name)
        value.name = name; value.pinned = true
        if value.order == nil { value.order = (preferences.values.compactMap(\.order).max() ?? 0) + 1 }
        preferences[id] = value
        persistPreferences(); refresh()
    }
    func resetApplicationAudio() {
        objectWillChange.send()
        for id in saved.keys where id.hasPrefix("app:") { saved[id] = .init() }
        for id in preferences.keys {
            preferences[id]?.outputUID = nil; preferences[id]?.outputName = nil
        }
        for app in apps { app.settings = .init() }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "soundMixerChannels") }
        persistPreferences(); refresh()
    }
    func togglePin(_ channel: SoundMixerChannel) {
        var value = preferences[channel.id] ?? SoundAppPreference(name: channel.name)
        value.pinned.toggle()
        value.order = (preferences.values.compactMap(\.order).max() ?? 0) + 1
        preferences[channel.id] = value; channel.preference = value
        persistPreferences(); sortApps()
    }
    func canMove(_ channel: SoundMixerChannel, by offset: Int) -> Bool {
        guard let from = apps.firstIndex(where: { $0.id == channel.id }), abs(offset) == 1 else { return false }
        let to = from + offset
        return apps.indices.contains(to) && apps[to].preference.pinned == channel.preference.pinned
    }
    func move(_ channel: SoundMixerChannel, by offset: Int) {
        preferences = SoundApplicationList.moving(channel.id, by: offset, ids: apps.map(\.id),
            names: Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.name) }), preferences: preferences)
        for app in apps { app.preference = preferences[app.id] ?? app.preference }
        persistPreferences(); sortApps()
    }
    private func persistPreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferencesKey) }
    }
    private func sortApps() {
        let map = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        let order = SoundApplicationList.ordered(apps.map(\.id), names: map.mapValues(\.name), preferences: preferences)
        if order != apps.map(\.id) { apps = order.compactMap { map[$0] } }
    }
    func resumeIfEnabled() { if requested { start() } }
    func start() {
        guard enabled(), available, !running, !starting else { return }
        requested = true; defaults.set(true, forKey: Self.enabledKey)
        if #available(macOS 14.2, *), observeHardware, !observingInput, !Snapshot.active { SoundProcessTap.cleanStaleVirtualInput() }
        refresh(); failure = nil; starting = true; generation += 1
        let token = generation
        let session = makeSession { [weak self] failure in
            guard let self, self.generation == token else { return }
            self.suspend(); self.failure = failure
        }
        self.session = session
        running = true; starting = false; watch(); updateActivityTimer()
        session.outputs(apps)
    }
    func stop() {
        requested = false; defaults.set(false, forKey: Self.enabledKey)
        suspend(); failure = nil
    }
    func suspend() {
        generation += 1; starting = false; running = false
        session?.stop(); session = nil; updateActivityTimer()
        apps.forEach { $0.hasAudio = false; $0.routeState = .stopped }
        if !visible, !observingInput { observations.removeAll(); refreshTask?.cancel(); refreshTask = nil }
    }
    private func watch() {
        observations.removeAll()
        guard observeHardware, !Snapshot.active else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        let changed: () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.enabled(), self.visible || self.running || self.observingInput else { return }
                self.refreshTask?.cancel()
                self.refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let self else { return }
                    self.refresh(); self.watch()
                }
            }
        }
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            if let observation = SoundHALObservation(system, selector, changed: changed) { observations.append(observation) }
        }
        for id in SoundHAL.ids(system, kAudioHardwarePropertyProcessObjectList) {
            if let observation = SoundHALObservation(id, kAudioProcessPropertyIsRunningOutput, changed: changed) { observations.append(observation) }
        }
    }
    private func refresh() {
        outputDevices = outputs().filter { SoundAppOutput.allows($0.uid) }
        let old = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
        var groups = Dictionary(uniqueKeysWithValues: discover().filter {
            SoundMixerDiscovery.allowsApplication($0.id)
                && ($0.sourceRunning || old[$0.id] != nil || preferences[$0.id]?.pinned == true)
        }.map { ($0.id, $0) })
        for (id, value) in preferences where value.pinned && groups[id] == nil && SoundMixerDiscovery.allowsApplication(id) {
            groups[id] = SoundMixerAppSnapshot(id: id, name: value.name, processes: [], appRunning: false, sourceRunning: false)
        }
        var metadataChanged = false
        var sourcesChanged = false
        var next: [SoundMixerChannel] = []
        for (id, info) in groups {
            let channel = old[id] ?? SoundMixerChannel(id: id, name: info.name, input: false, settings: saved["app:" + id] ?? .init())
            channel.name = info.name; channel.appRunning = info.appRunning; channel.sourceRunning = info.sourceRunning
            channel.updateIcon(info.iconURL)
            channel.settings.gain = min(1, channel.settings.safeGain); channel.settings.active = true; channel.settings.bass = false
            let connected = info.sourceRunning ? info.processes : channel.processes.filter { info.processes.contains($0) }
            if channel.processes != connected.sorted() { sourcesChanged = true }
            channel.processes = connected.sorted()
            var preference = preferences[id] ?? SoundAppPreference(name: info.name)
            preference.name = info.name
            if let uid = preference.outputUID, let device = outputDevices.first(where: { $0.uid == uid }) { preference.outputName = device.name }
            if preferences[id] != preference { preferences[id] = preference; metadataChanged = true }
            channel.preference = preference
            next.append(channel)
        }
        let map = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        let order = SoundApplicationList.ordered(Array(map.keys), names: map.mapValues(\.name), preferences: preferences)
        if order != apps.map(\.id) { apps = order.compactMap { map[$0] } }
        if sourcesChanged { sourceRevision += 1 }
        if metadataChanged { persistPreferences() }
        session?.outputs(apps); sampleActivity()
    }
    private func updateActivityTimer() {
        activityTimer?.invalidate(); activityTimer = nil
        guard visible, running, !Snapshot.active else { return }
        activityTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleActivity() }
        }
    }
    private func sampleActivity() {
        guard visible else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for app in apps {
            if running, app.sourceRunning, (session?.sourceLevel(app.id) ?? 0) > 0.0001 { app.lastSignal = now }
            let active = running && app.sourceRunning && now - app.lastSignal < 0.5
            if active != app.hasAudio { app.hasAudio = active }
        }
    }
    func stageDemo(enabled: Bool = true) {
        if Snapshot.active { requested = enabled; running = enabled }
        apps = [SoundMixerChannel(id: "com.apple.Safari", name: "Safari", input: false, settings: .init()),
                SoundMixerChannel(id: "com.apple.Music", name: "Music", input: false, settings: .init())]
        apps[0].settings.gain = 0.65; apps[0].hasAudio = true; apps[0].processes = [1]
        apps[0].preference.pinned = true; apps[0].routeState = .playing("demo")
        apps[1].settings.gain = 0.3; apps[1].processes = [2]; apps[1].routeState = .playing("demo")
    }
}
