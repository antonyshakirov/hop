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
    var sourceGuarded: Bool { get }
    var preparingOutput: Bool { get }
    var outputReady: Bool { get }
    func setOutput(_ uid: String?, followsSystem: Bool) throws
    func waitUntilOutputReady() async throws
    func activateOutput() throws
    func update(_ settings: SoundChannelSettings, outputUID: String?, followsSystem: Bool, masterUID: String?) throws
}
extension SoundAppOutputStream {
    var sourceGuarded: Bool { true }
    var preparingOutput: Bool { false }
    var outputReady: Bool { true }
    func setOutput(_ uid: String?, followsSystem: Bool) throws { try setOutput(uid) }
    func waitUntilOutputReady() async throws {}
    func activateOutput() throws {}
    func update(_ settings: SoundChannelSettings, outputUID: String?, followsSystem: Bool, masterUID: String?) throws {
        if let current = self.outputUID, current != outputUID { try setOutput(nil, followsSystem: false) }
        configure(settings)
        try setOutput(outputUID, followsSystem: followsSystem)
    }
}

@available(macOS 14.2, *)
final class SoundOutputStream: SoundAppOutputStream, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    let tap: SoundProcessTap
    let channel: SoundAudioChannel
    private var playback: SoundAppPlayback?
    private var fallbackGuard: SoundProcessTap?
    private let processes: [AudioObjectID]
    private var stopped = false
    private var requestedUID: String?
    private var followsSystem = false
    private var settings: SoundChannelSettings
    private var activated = false
    private let configuration = SoundOutputConfigurationBoundary()
    private lazy var handoff = SoundOutputHandoff(setSourceMuted: { [unowned self] in try self.tap.setSourceMuted($0) },
        setPlaybackEnabled: { [unowned self] in hop_audio_set_playback_enabled(self.channel.pointer, $0) },
        releaseSource: { [unowned self] in
            self.tap.release(); self.fallbackGuard?.release(); self.fallbackGuard = nil
        },
        stopPlayback: { [unowned self] in self.playback?.stop(); self.playback = nil },
        discardQueued: { [unowned self] in hop_audio_discard_queued(self.channel.pointer) },
        fallbackSourceGuard: { [unowned self] in
            if self.fallbackGuard == nil {
                self.fallbackGuard = try SoundProcessTap(processes: self.processes,
                    name: "Hop App Output Guard", holdSourceMuted: true)
            }
        })
    private let changed: @Sendable () -> Void

    init(processes: [AudioObjectID], settings: SoundChannelSettings, outputUID: String? = nil, followsSystem: Bool = false,
         changed: @escaping @Sendable () -> Void) throws {
        self.processes = processes; self.changed = changed; self.settings = settings; self.followsSystem = followsSystem; requestedUID = outputUID
        try Task.checkCancellation()
        let guarded = SoundOutputHandoff.needsGuard(outputUID: outputUID, followsSystem: followsSystem, settings: settings)
        tap = try SoundProcessTap(processes: processes, name: "Hop App Output", holdSourceMuted: guarded, warmupUnmuted: !guarded)
        channel = try SoundAudioChannel(rate: tap.format.sampleRate)
        channel.configure(settings)
        hop_audio_compensate_clock(channel.pointer)
        try handoff.prepare(outputUID: outputUID, followsSystem: followsSystem, settings: settings)
        try Task.checkCancellation()
        try tap.start(channel)
        do { try Task.checkCancellation() } catch { tap.stop(); throw error }
    }
    var outputUID: String? { lock.withLock { activated && playback?.isValid == true ? playback?.uid : nil } }
    var sourceGuarded: Bool { lock.withLock { handoff.sourceGuarded } }
    var preparingOutput: Bool { lock.withLock { !stopped && !activated && requestedUID != nil && playback != nil } }
    var outputReady: Bool {
        lock.withLock { requestedUID == nil || (playback?.isValid == true && hop_audio_playback_ready(channel.pointer)) }
    }
    var sourcePeak: Float { hop_audio_source_peak(channel.pointer) }
    func update(_ settings: SoundChannelSettings, outputUID: String?, followsSystem: Bool, masterUID: String?) throws {
        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            do {
                try configuration.transition(outputUID: outputUID, masterUID: masterUID,
                    playback: { (self.playback.map(ObjectIdentifier.init), requestedUID, activated) },
                    gate: { hop_audio_set_playback_enabled(channel.pointer, false) }) {
                    self.settings = settings; channel.configure(settings)
                    try setOutput(outputUID, followsSystem: followsSystem)
                } activate: { try activateOutput() }
            } catch { activated = false; try? handoff.fail(); throw error }
        }
    }
    func configure(_ settings: SoundChannelSettings) {
        lock.withLock {
            self.settings = settings; channel.configure(settings)
            do { try handoff.reconcile(outputUID: requestedUID, followsSystem: followsSystem, settings: settings) }
            catch { activated = false; try? handoff.fail(); changed() }
        }
    }
    func setOutput(_ uid: String?) throws { try setOutput(uid, followsSystem: followsSystem) }
    func setOutput(_ uid: String?, followsSystem: Bool) throws {
        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            self.followsSystem = followsSystem; requestedUID = uid
            do {
                try handoff.reconcile(outputUID: uid, followsSystem: followsSystem, settings: settings)
                if let uid, playback?.uid == uid, playback?.isValid == true { return }
                activated = false
                try handoff.prepare(outputUID: uid, followsSystem: followsSystem, settings: settings)
                playback?.stop(); playback = nil
                hop_audio_discard_queued(channel.pointer)
                guard let uid else { return }
                playback = try SoundAppPlayback(uid: uid, channel: channel, changed: changed)
            } catch { activated = false; try? handoff.fail(); throw error }
        }
    }
    func waitUntilOutputReady() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            try Task.checkCancellation()
            let ready = try lock.withLock {
                guard !stopped else { throw CancellationError() }
                if requestedUID == nil { try handoff.acquireGuard(); return true }
                guard playback?.isValid == true else { try handoff.fail(); throw SoundFailure.missingDevice }
                guard hop_audio_playback_ready(channel.pointer) else { return false }
                do { try handoff.acquireGuard() }
                catch { try? handoff.fail(); throw error }
                return true
            }
            if ready { return }
            guard ContinuousClock.now < deadline else {
                try lock.withLock { try handoff.fail() }
                throw SoundFailure.system(-1)
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
    func activateOutput() throws {
        try lock.withLock {
            guard !stopped else { throw CancellationError() }
            if let uid = requestedUID {
                guard playback?.isValid == true, hop_audio_playback_ready(channel.pointer) else {
                    activated = false
                    try handoff.fail()
                    throw SoundFailure.missingDevice
                }
                activated = try handoff.ready(for: uid)
            }
        }
    }
    func stop() {
        lock.withLock {
            guard !stopped else { return }
            stopped = true; activated = false; handoff.stop()
        }
    }
    deinit {
        hop_audio_set_playback_enabled(channel.pointer, false)
        tap.release(); fallbackGuard?.release(); playback?.stop()
    }
}

@available(macOS 14.2, *)
private final class SoundAppPlayback {
    let uid: String
    private let device: AudioObjectID
    private let engine = AVAudioEngine()
    private var observation: NSObjectProtocol?
    var isValid: Bool {
        engine.isRunning && engine.outputNode.auAudioUnit.deviceID == device
            && SoundHAL.value(device, kAudioDevicePropertyDeviceIsAlive, UInt32(0)) == 1
    }

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
