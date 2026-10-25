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
    private let failed: (SoundFailure) -> Void
    private let devices: () -> [SoundDevice]
    private let systemUID: () -> String?
    private let makeStream: Factory

    init(failed: @escaping (SoundFailure) -> Void,
         devices: (() -> [SoundDevice])? = nil,
         systemUID: (() -> String?)? = nil,
         makeStream: Factory? = nil) {
        let hardware = CoreSoundHardware()
        self.failed = failed
        self.devices = devices ?? { hardware.devices(.output) }
        self.systemUID = systemUID ?? { hardware.defaultUID(.output) }
        self.makeStream = makeStream ?? { processes, settings, changed in
            let task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                return try SoundOutputStream(processes: processes, settings: settings, changed: changed)
            }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        }
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
            if streams[channel.id] != nil { apply(channel) }
        }
    }
    private func prepare(_ channel: SoundMixerChannel) {
        let id = channel.id, ids = channel.processes, settings = channel.settings, token = UUID()
        tokens[id] = token; processes[id] = ids; channel.routeState = .preparing
        pending[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.makeStream(ids, settings, { [weak self] in
                    Task { @MainActor in
                        guard let self, self.activeTokens[id] == token, let latest = self.channels[id] else { return }
                        self.apply(latest)
                    }
                })
                guard !Task.isCancelled, self.tokens[id] == token,
                      let latest = self.channels[id], latest.processes == ids else { stream.stop(); return }
                let previous = self.streams[id]
                try? previous?.setOutput(nil)
                self.pending[id] = nil; self.streams[id] = stream; self.activeTokens[id] = token
                self.apply(latest)
                previous?.stop()
            } catch {
                guard self.tokens[id] == token, let latest = self.channels[id] else { return }
                self.pending[id] = nil; self.processes[id] = nil; self.tokens[id] = nil
                latest.routeState = .failed
                if self.streams.isEmpty { self.failed(error as? SoundFailure ?? .system(-1)) }
            }
        }
    }
    private func apply(_ channel: SoundMixerChannel) {
        guard let stream = streams[channel.id] else { return }
        stream.configure(channel.settings)
        let target = SoundAppOutput.resolve(selectedUID: channel.preference.outputUID,
            systemUID: systemUID(), available: Set(devices().map(\.uid)))
        do {
            try stream.setOutput(target)
            if let target, stream.outputUID == target { channel.routeState = .playing(target) }
            else { channel.routeState = target == nil ? .waiting : .failed }
        } catch {
            try? stream.setOutput(nil)
            channel.routeState = .failed
        }
    }
    func configure(_ channel: SoundMixerChannel) {
        guard !channel.input, channels[channel.id] != nil else { return }
        apply(channel)
    }
    func sourceLevel(_ id: String) -> Float { streams[id]?.sourcePeak ?? 0 }
    private func retire(_ id: String) {
        tokens[id] = nil; activeTokens[id] = nil
        pending.removeValue(forKey: id)?.cancel()
        streams.removeValue(forKey: id)?.stop()
        processes[id] = nil
    }
    func stop() {
        channels.values.forEach { $0.routeState = .stopped }
        channels.removeAll()
        for id in Set(processes.keys).union(streams.keys) { retire(id) }
    }
}
