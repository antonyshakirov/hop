import CoreAudio
import Foundation
import HopAudioDSP
import HopCore

public final class SoundInputMixGate: @unchecked Sendable {
    private let lock = NSLock()
    private var microphones: [(SoundAudioChannel, SoundChannelSettings)] = []
    private var applications: [SoundAudioChannel] = []
    private var token: UUID?
    private var microphoneMuted = false

    public init() {}

    public var muted: Bool {
        lock.lock(); defer { lock.unlock() }
        return microphoneMuted
    }

    public func replace(microphones: [(SoundAudioChannel, SoundChannelSettings)], applications: [SoundAudioChannel],
                        token: UUID?, muted: Bool? = nil) {
        lock.lock(); defer { lock.unlock() }
        if self.token != token { microphoneMuted = muted ?? false }
        self.microphones = microphones; self.applications = applications; self.token = token
        if token == nil { microphoneMuted = false }
        configureMicrophones()
    }

    @discardableResult
    public func setMuted(_ value: Bool, token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard self.token == token, !microphones.isEmpty else { return false }
        microphoneMuted = value; configureMicrophones()
        return true
    }

    private func configureMicrophones() {
        for (channel, original) in microphones {
            var settings = original; settings.muted = original.muted || microphoneMuted
            channel.configure(settings)
        }
    }

    public func render(_ output: UnsafeMutablePointer<AudioBufferList>, frames: UInt32) {
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard lock.try() else { return }
        defer { lock.unlock() }
        for (channel, _) in microphones { hop_audio_render(channel.pointer, output, frames, true) }
        for channel in applications { hop_audio_render(channel.pointer, output, frames, true) }
        hop_audio_limit(output, frames)
    }
}
