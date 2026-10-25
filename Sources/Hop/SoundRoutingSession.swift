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
    private let systemUID: () -> String?
    private let makeStream: Factory?

    init(failed: @escaping (SoundFailure) -> Void,
         devices: (() -> [SoundDevice])? = nil,
         systemUID: (() -> String?)? = nil,
         makeStream: Factory? = nil) {
        let hardware = CoreSoundHardware()
        self.failed = failed
        self.devices = devices ?? { hardware.devices(.output) }
        self.systemUID = systemUID ?? { hardware.defaultUID(.output) }
        self.makeStream = makeStream
        try? SoundAccessoryMute.shared.install()
    }
    func outputs(_ channels: [SoundMixerChannel]) {
        self.channels = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0) })
        for id in Set(processes.keys).union(streams.keys) where self.channels[id] == nil || self.channels[id]?.processes.isEmpty == true {
            retire(id)
        }
        for channel in channels where !channel.input {
            guard !channel.processes.isEmpty else { channel.routeState = .stopped; continue }
            if processes[channel.id] != channel.processes || (streams[channel.id] == nil && pending[channel.id] == nil) {
                pending.removeValue(forKey: channel.id)?.cancel()
                prepare(channel)
            }
            if let stream = pendingStreams[channel.id] {
                do { try configurePending(channel, stream: stream) }
                catch { channel.routeState = .failed }
            }
            if streams[channel.id] != nil { apply(channel) }
        }
    }
    private func prepare(_ channel: SoundMixerChannel) {
        let id = channel.id, ids = channel.processes, settings = channel.settings, token = UUID()
        pendingStreams.removeValue(forKey: id)?.stop()
        tokens[id] = token; processes[id] = ids; channel.routeState = .preparing
        pending[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let changed: @Sendable () -> Void = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.activeTokens[id] == token, let latest = self.channels[id] else { return }
                        self.apply(latest)
                    }
                }
                let stream: any SoundAppOutputStream
                if let makeStream = self.makeStream { stream = try await makeStream(ids, settings, changed) }
                else {
                    let outputUID = self.target(channel), followsSystem = channel.preference.outputUID == nil
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
                try self.configurePending(latest, stream: stream)
                repeat {
                    try await stream.waitUntilOutputReady()
                    try Task.checkCancellation()
                    guard self.tokens[id] == token, let current = self.channels[id], current.processes == ids else {
                        stream.stop(); return
                    }
                    try self.configurePending(current, stream: stream)
                } while !stream.outputReady
                guard stream.sourceGuarded else { throw SoundFailure.system(-1) }
                let previous = self.streams[id]
                self.cancelActivation(id)
                try previous?.setOutput(nil, followsSystem: false)
                try stream.activateOutput()
                self.pendingStreams[id] = nil
                self.pending[id] = nil; self.streams[id] = stream; self.activeTokens[id] = token
                self.reflect(latest, stream: stream)
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
                if self.streams[id] != nil { self.apply(latest) }
                if self.streams.isEmpty { self.failed(error as? SoundFailure ?? .system(-1)) }
            }
        }
    }
    private func target(_ channel: SoundMixerChannel) -> String? {
        SoundAppOutput.resolve(selectedUID: channel.preference.outputUID,
            systemUID: systemUID(), available: Set(devices().map(\.uid)))
    }
    private func configurePending(_ channel: SoundMixerChannel, stream: any SoundAppOutputStream) throws {
        stream.configure(channel.settings)
        try stream.setOutput(target(channel), followsSystem: channel.preference.outputUID == nil)
    }
    private func reflect(_ channel: SoundMixerChannel, stream: any SoundAppOutputStream) {
        if let target = target(channel), stream.outputUID == target { channel.routeState = .playing(target) }
        else if target(channel) == nil { channel.routeState = .waiting }
        else { channel.routeState = stream.preparingOutput ? .preparing : .failed }
    }
    private func apply(_ channel: SoundMixerChannel) {
        guard let stream = streams[channel.id] else { return }
        do {
            try configurePending(channel, stream: stream)
            reflect(channel, stream: stream)
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
                    try await stream.waitUntilOutputReady()
                    try Task.checkCancellation()
                    guard self.activationIDs[id] == activationID, self.streams[id] === stream,
                          let latest = self.channels[id] else { return }
                    try stream.activateOutput(); self.reflect(latest, stream: stream)
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
    func configure(_ channel: SoundMixerChannel) {
        guard !channel.input, channels[channel.id] != nil else { return }
        if let stream = pendingStreams[channel.id] {
            do { try configurePending(channel, stream: stream) }
            catch { channel.routeState = .failed }
        }
        apply(channel)
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
        channels.values.forEach { $0.routeState = .stopped }
        channels.removeAll()
        for id in Set(processes.keys).union(streams.keys).union(pendingStreams.keys) { retire(id) }
    }
}
