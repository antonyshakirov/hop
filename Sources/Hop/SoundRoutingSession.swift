import CoreAudio
import HopCore
import HopAudioEngine

@available(macOS 14.2, *)
@MainActor
final class SoundRoutingSession: SoundMixingSession {
    typealias Factory = ([AudioObjectID], SoundChannelSettings, @escaping @Sendable () -> Void) async throws -> any SoundAppOutputStream
    private var streams: [String: any SoundAppOutputStream] = [:]
    private var processes: [String: [AudioObjectID]] = [:]
    private var activeTokens: [String: UUID] = [:]
    private var tokens: [String: UUID] = [:]
    private var pending: [String: Task<Void, Never>] = [:]
    private var channels: [String: SoundMixerChannel] = [:]
    private var pendingStreams: [String: any SoundAppOutputStream] = [:]
    private var activations: [String: Task<Void, Never>] = [:]
    private var activationIDs: [String: UUID] = [:]
    private let failed: (SoundFailure) -> Void
    private let devices: () -> [SoundDevice]
    private let master: any SoundListeningMasterSource
    private var observing = false
    private var observationID = UUID()
    private var refresh: Task<Void, Never>?
    private let makeStream: Factory?
    private struct Context {
        let master: SoundListeningMasterSnapshot
        let available: Set<String>
    }
    private func context() -> Context { Context(master: master.snapshot(), available: Set(devices().map(\.uid))) }

    init(failed: @escaping (SoundFailure) -> Void,
         devices: (() -> [SoundDevice])? = nil,
         systemUID: (() -> String?)? = nil,
         makeStream: Factory? = nil,
         master: (any SoundListeningMasterSource)? = nil) {
        let hardware = CoreSoundHardware()
        self.failed = failed
        self.devices = devices ?? { hardware.devices(.output) }
        if let master { self.master = master }
        else if devices != nil || systemUID != nil {
            let readDevices = self.devices
            let readUID = systemUID ?? { hardware.defaultUID(.output) }
            self.master = SoundListeningMasterObserver(read: {
                let uid = readUID(), device = readDevices().first { $0.uid == uid }
                return SoundListeningMasterSnapshot(uid: uid, scalar: device?.volume, muted: device?.muted)
            })
        } else {
            self.master = SoundListeningMasterObserver(read: { hardware.listeningMaster() },
                watch: { hardware.watchListeningMaster($0) }, unwatch: { hardware.unwatch() })
        }
        self.makeStream = makeStream
        try? SoundAccessoryMute.shared.install()
    }
    func outputs(_ channels: [SoundMixerChannel]) {
        startObservation()
        let context = context()
        self.channels = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        for id in Set(processes.keys).union(streams.keys) where self.channels[id] == nil || self.channels[id]?.processes.isEmpty == true {
            retire(id)
        }
        for channel in channels where !channel.input {
            guard !channel.processes.isEmpty else { channel.routeState = .stopped; continue }
            if processes[channel.id] != channel.processes || (streams[channel.id] == nil && pending[channel.id] == nil) {
                pending.removeValue(forKey: channel.id)?.cancel()
                prepare(channel, context: context)
            }
            if let stream = pendingStreams[channel.id] {
                do { try configurePending(channel, stream: stream, context: context) }
                catch { channel.routeState = .failed }
            }
            if streams[channel.id] != nil { apply(channel, context: context) }
        }
    }
    private func prepare(_ channel: SoundMixerChannel, context: Context) {
        let id = channel.id, ids = channel.processes, token = UUID()
        let settings = effective(channel, context: context)
        pendingStreams.removeValue(forKey: id)?.stop()
        tokens[id] = token; processes[id] = ids; channel.routeState = .preparing
        pending[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let changed: @Sendable () -> Void = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.activeTokens[id] == token, let latest = self.channels[id] else { return }
                        self.apply(latest, context: self.context())
                    }
                }
                let stream: any SoundAppOutputStream
                if let makeStream = self.makeStream { stream = try await makeStream(ids, settings, changed) }
                else {
                    let outputUID = self.target(channel, context: context), followsSystem = channel.preference.outputUID == nil
                    let build = Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        return try SoundOutputStream(processes: ids, settings: settings, outputUID: outputUID,
                            followsSystem: followsSystem, changed: changed)
                    }
                    stream = try await withTaskCancellationHandler { try await build.value } onCancel: { build.cancel() }
                }
                guard !Task.isCancelled, self.tokens[id] == token,
                      let latest = self.channels[id], latest.processes == ids else { stream.stop(); return }
                self.pendingStreams[id] = stream
                var latestContext = self.context()
                try self.configurePending(latest, stream: stream, context: latestContext)
                repeat {
                    try await stream.waitUntilOutputReady()
                    try Task.checkCancellation()
                    guard self.tokens[id] == token, let current = self.channels[id], current.processes == ids else {
                        stream.stop(); return
                    }
                    latestContext = self.context()
                    try self.configurePending(current, stream: stream, context: latestContext)
                } while !stream.outputReady
                guard stream.sourceGuarded else { throw SoundFailure.system(-1) }
                let previous = self.streams[id]
                self.cancelActivation(id)
                try previous?.setOutput(nil, followsSystem: false)
                try stream.activateOutput()
                self.pendingStreams[id] = nil
                self.pending[id] = nil; self.streams[id] = stream; self.activeTokens[id] = token
                self.reflect(latest, stream: stream, context: latestContext)
                previous?.stop()
            } catch {
                guard self.tokens[id] == token, let latest = self.channels[id] else { return }
                if let stream = self.pendingStreams.removeValue(forKey: id) {
                    if self.streams[id] == nil, stream.sourceGuarded {
                        self.streams[id] = stream; self.activeTokens[id] = token
                    } else { stream.stop() }
                }
                self.pending[id] = nil; self.processes[id] = nil; self.tokens[id] = nil
                latest.routeState = .failed
                if self.streams[id] != nil { self.apply(latest, context: self.context()) }
                if self.streams.isEmpty { self.failed(error as? SoundFailure ?? .system(-1)) }
            }
        }
    }
    private func target(_ channel: SoundMixerChannel, context: Context) -> String? {
        SoundAppOutput.resolve(selectedUID: channel.preference.outputUID,
            systemUID: context.master.uid, available: context.available)
    }
    private func effective(_ channel: SoundMixerChannel, context: Context) -> SoundChannelSettings {
        var settings = channel.settings
        if let uid = target(channel, context: context), uid != context.master.uid {
            settings.gain = settings.safeGain * context.master.attenuation
        }
        settings.muted = settings.muted || context.master.muted
        return settings
    }
    private func configurePending(_ channel: SoundMixerChannel, stream: any SoundAppOutputStream, context: Context) throws {
        try stream.update(effective(channel, context: context), outputUID: target(channel, context: context),
            followsSystem: channel.preference.outputUID == nil, masterUID: context.master.uid)
    }
    private func startObservation() {
        guard !observing else { return }
        observing = true
        let id = UUID(); observationID = id
        master.start { [weak self] in
            guard let self, self.observing, self.observationID == id, self.refresh == nil else { return }
            self.refresh = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled, self.observing, self.observationID == id else { return }
                self.refresh = nil
                let context = self.context()
                for channel in self.channels.values where !channel.input { self.configure(channel, context: context) }
            }
        }
    }
    private func reflect(_ channel: SoundMixerChannel, stream: any SoundAppOutputStream, context: Context) {
        let target = target(channel, context: context)
        if let target, stream.outputUID == target { channel.routeState = .playing(target) }
        else if target == nil { channel.routeState = .waiting }
        else { channel.routeState = stream.preparingOutput ? .preparing : .failed }
    }
    private func apply(_ channel: SoundMixerChannel, context: Context) {
        guard let stream = streams[channel.id] else { return }
        do {
            try configurePending(channel, stream: stream, context: context)
            reflect(channel, stream: stream, context: context)
            guard stream.preparingOutput, activations[channel.id] == nil else { return }
            let id = channel.id, activationID = UUID()
            activationIDs[id] = activationID
            activations[id] = Task { [weak self, weak stream] in
                guard let self, let stream else { return }
                defer {
                    if self.activationIDs[id] == activationID {
                        self.activationIDs[id] = nil; self.activations[id] = nil
                    }
                }
                do {
                    var latestContext = context
                    repeat {
                        try await stream.waitUntilOutputReady()
                        try Task.checkCancellation()
                        guard self.activationIDs[id] == activationID, self.streams[id] === stream,
                              let latest = self.channels[id] else { return }
                        latestContext = self.context()
                        try self.configurePending(latest, stream: stream, context: latestContext)
                    } while !stream.outputReady
                    guard let latest = self.channels[id] else { return }
                    try stream.activateOutput(); self.reflect(latest, stream: stream, context: latestContext)
                } catch {
                    guard self.activationIDs[id] == activationID, self.streams[id] === stream else { return }
                    self.channels[id]?.routeState = .failed
                }
            }
        } catch {
            try? stream.setOutput(nil, followsSystem: false)
            channel.routeState = .failed
        }
    }
    func configure(_ channel: SoundMixerChannel) { configure(channel, context: context()) }
    private func configure(_ channel: SoundMixerChannel, context: Context) {
        guard !channel.input, channels[channel.id] != nil else { return }
        if let stream = pendingStreams[channel.id] {
            do { try configurePending(channel, stream: stream, context: context) }
            catch { channel.routeState = .failed }
        }
        apply(channel, context: context)
    }
    func sourceLevel(_ id: String) -> Float { streams[id]?.sourcePeak ?? 0 }
    private func cancelActivation(_ id: String) {
        activationIDs[id] = nil
        activations.removeValue(forKey: id)?.cancel()
    }
    private func retire(_ id: String) {
        tokens[id] = nil; activeTokens[id] = nil
        pending.removeValue(forKey: id)?.cancel()
        cancelActivation(id)
        pendingStreams.removeValue(forKey: id)?.stop()
        streams.removeValue(forKey: id)?.stop()
        processes[id] = nil
    }
    func stop() {
        observing = false; observationID = UUID()
        refresh?.cancel(); refresh = nil; master.stop()
        channels.values.forEach { $0.routeState = .stopped }
        channels.removeAll()
        for id in Set(processes.keys).union(streams.keys).union(pendingStreams.keys) { retire(id) }
    }
}
