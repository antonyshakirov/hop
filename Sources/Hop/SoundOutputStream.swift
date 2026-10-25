import AVFoundation
import CoreAudio
import HopAudioDSP
import HopAudioEngine
import HopCore

/// A capture/muting guard survives replacing or losing its listening output.
protocol SoundAppOutputStream: AnyObject, Sendable {
    var outputUID: String? { get }
    var sourcePeak: Float { get }
    func configure(_ settings: SoundChannelSettings)
    func setOutput(_ uid: String?) throws
    func stop()
}

@available(macOS 14.2, *)
final class SoundOutputStream: SoundAppOutputStream, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let tap: SoundProcessTap
    let channel: SoundAudioChannel
    private var playback: SoundAppPlayback?
    private var stopped = false
    private let changed: @Sendable () -> Void

    init(processes: [AudioObjectID], settings: SoundChannelSettings,
         changed: @escaping @Sendable () -> Void) throws {
        self.changed = changed
        try Task.checkCancellation()
        tap = try SoundProcessTap(processes: processes, name: "Hop App Output", holdSourceMuted: true)
        channel = try SoundAudioChannel(rate: tap.format.sampleRate)
        channel.configure(settings)
        hop_audio_compensate_clock(channel.pointer)
        try Task.checkCancellation()
        try tap.start(channel)
        do { try Task.checkCancellation() } catch { tap.stop(); throw error }
    }
    var outputUID: String? { lock.withLock { playback?.isValid == true ? playback?.uid : nil } }
    var sourcePeak: Float { hop_audio_source_peak(channel.pointer) }
    func configure(_ settings: SoundChannelSettings) { channel.configure(settings) }
    func setOutput(_ uid: String?) throws {
        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            if let uid, playback?.uid == uid, playback?.isValid == true { return }
            playback?.stop(); playback = nil
            hop_audio_discard_queued(channel.pointer)
            guard let uid else { return }
            playback = try SoundAppPlayback(uid: uid, channel: channel, changed: changed)
        }
    }
    func stop() {
        lock.withLock {
            guard !stopped else { return }
            stopped = true
            playback?.stop(); playback = nil
            tap.stop()
        }
    }
    deinit { stop() }
}

@available(macOS 14.2, *)
private final class SoundAppPlayback {
    let uid: String
    private let device: AudioObjectID
    private let engine = AVAudioEngine()
    private var observation: NSObjectProtocol?
    var isValid: Bool { engine.isRunning && engine.outputNode.auAudioUnit.deviceID == device }

    init(uid: String, channel: SoundAudioChannel, changed: @escaping @Sendable () -> Void) throws {
        self.uid = uid
        guard let device = SoundHAL.device(uid),
              SoundHAL.value(device, kAudioDevicePropertyDeviceIsAlive, UInt32(0)) == 1 else { throw SoundFailure.missingDevice }
        self.device = device
        let output = engine.outputNode
        try output.auAudioUnit.setDeviceID(device)
        let hardware = output.outputFormat(forBus: 0)
        guard hardware.sampleRate.isFinite, hardware.sampleRate > 0, hardware.channelCount > 0,
              output.auAudioUnit.deviceID == device else { throw SoundFailure.unsupported }
        let format = AVAudioFormat(standardFormatWithSampleRate: channel.sampleRate, channels: 2)!
        let source = AVAudioSourceNode(format: format) { _, _, frames, buffers in
            hop_audio_render(channel.pointer, buffers, frames, false); return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: output, format: nil)
        do {
            try engine.start()
            guard output.auAudioUnit.deviceID == device,
                  SoundHAL.value(device, kAudioDevicePropertyDeviceIsAlive, UInt32(0)) == 1 else { throw SoundFailure.missingDevice }
        } catch { engine.stop(); throw error }
        observation = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { [weak engine] _ in
            guard let engine, !engine.isRunning || engine.outputNode.auAudioUnit.deviceID != device else { return }
            engine.stop()
            changed() // The session resolves the latest UID; never restart at a default device here.
        }
    }
    func stop() {
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil; engine.stop()
    }
    deinit { stop() }
}
