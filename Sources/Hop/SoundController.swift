import AVFoundation
import Combine
import Foundation
import HopCore

@MainActor
protocol SoundMeter: AnyObject {
    var level: Double { get }
    var permitted: Bool { get }
    var peak: Double { get }
    var duration: Double { get }
    var hasRecording: Bool { get }
    func play(_ completed: @escaping () -> Void) throws
    func stopPlayback()
    func clearRecording()
    func requestAccess(_ completion: @escaping (Bool) -> Void)
    func start(_ uid: String, _ interrupted: @escaping () -> Void) throws
    func stop()
}

extension SoundMeter {
    var peak: Double { level }
    var duration: Double { 0 }
    var hasRecording: Bool { false }
    func play(_ completed: @escaping () -> Void) throws { throw SoundFailure.unsupported }
    func stopPlayback() {}
    func clearRecording() {}
}

@MainActor
final class MicrophoneLevelMeter: SoundMeter {
    static let privacySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    private var engine: AVAudioEngine?
    private var observation: NSObjectProtocol?
    private var samples: SoundSampleBuffer?
    private var playback: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playbackGeneration = 0
    var level: Double { samples?.readings.level ?? 0 }
    var peak: Double { samples?.readings.peak ?? 0 }
    var duration: Double { samples?.readings.duration ?? 0 }
    var hasRecording: Bool { duration >= 0.1 }
    var permitted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async { completion(allowed) }
            }
        default: completion(false)
        }
    }

    func start(_ uid: String, _ interrupted: @escaping () -> Void) throws {
        stop()
        clearRecording()
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { throw SoundFailure.permission }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let deviceID = try CoreSoundHardware().objectID(uid, direction: .input)
        if input.auAudioUnit.deviceID != deviceID { try input.auAudioUnit.setDeviceID(deviceID) }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SoundFailure.missingDevice }
        let samples = try SoundSampleBuffer(format: format)
        self.samples = samples
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in samples.append(buffer) }
        do { try engine.start() }
        catch { input.removeTap(onBus: 0); engine.stop(); throw error }
        self.engine = engine
        observation = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak engine] _ in
            MainActor.assumeIsolated {
                if engine?.isRunning == false { interrupted() }
            }
        }
    }

    func stop() {
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    func play(_ completed: @escaping () -> Void) throws {
        guard engine == nil, let recorded = samples?.recorded(), hasRecording else { throw SoundFailure.unsupported }
        stopPlayback()
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: recorded.format)
        try engine.start()
        playback = engine
        self.player = player
        let token = playbackGeneration
        player.scheduleBuffer(recorded, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == token else { return }
                self.stopPlayback()
                completed()
            }
        }
        player.play()
    }

    func stopPlayback() {
        playbackGeneration += 1
        player?.stop()
        playback?.stop()
        player = nil
        playback = nil
    }

    func clearRecording() {
        stopPlayback()
        samples = nil
    }
}

@MainActor
final class SoundLiveReadings: ObservableObject {
    @Published var level = 0.0
    @Published var peak = 0.0
    @Published var duration = 0.0
}

@MainActor
final class SoundController: ObservableObject {
    @Published private(set) var outputs: [SoundDevice] = []
    @Published private(set) var inputs: [SoundDevice] = []
    @Published private(set) var outputUID: String?
    @Published private(set) var inputUID: String?
    @Published private(set) var checking = false
    @Published private(set) var requestingAccess = false
    let readings = SoundLiveReadings()
    private(set) var level: Double { get { readings.level } set { readings.level = newValue } }
    private(set) var peak: Double { get { readings.peak } set { readings.peak = newValue } }
    private(set) var duration: Double { get { readings.duration } set { readings.duration = newValue } }
    @Published private(set) var hasRecording = false
    @Published private(set) var playing = false
    @Published private(set) var outputFollowsSystem = true
    @Published private(set) var inputFollowsSystem = true
    @Published private(set) var failure: SoundFailure?
    private(set) var windowOpen = false
    private let hardware: SoundHardware
    private let meter: SoundMeter
    private let enabled: @MainActor () -> Bool
    private var ticker: Timer?
    private var generation = 0
    private var volumeTasks: [SoundDirection: Task<Void, Never>] = [:]
    private var volumeGenerations: [SoundDirection: Int] = [:]
    private var volumeRequests: [SoundDirection: (value: Double, uid: String)] = [:]
    private var playbackGeneration = 0
    private let status: SoundMuteStatus?

    init(hardware: SoundHardware? = nil, meter: SoundMeter? = nil,
         enabled: (@MainActor () -> Bool)? = nil, status: SoundMuteStatus? = nil) {
        self.status = status
        self.hardware = hardware ?? CoreSoundHardware()
        self.meter = meter ?? MicrophoneLevelMeter()
        self.enabled = enabled ?? { ModuleActivation.isOn("sound") }
    }

    func device(_ direction: SoundDirection) -> SoundDevice? {
        let uid = direction == .output ? outputUID : inputUID
        return (direction == .output ? outputs : inputs).first { $0.uid == uid }
    }

    func open() {
        guard enabled(), !windowOpen else { return }
        windowOpen = true
        refresh()
        hardware.watch { [weak self] in self?.refresh() }
    }

    func close() {
        windowOpen = false
        stopCheck()
        discardRecording()
        for task in volumeTasks.values { task.cancel() }
        volumeTasks.removeAll()
        volumeRequests.removeAll()
        hardware.unwatch()
        failure = nil
    }

    func refresh() {
        guard enabled() else { close(); return }
        let previousInput = inputUID, previousOutput = outputUID
        outputs = hardware.devices(.output)
        inputs = hardware.devices(.input)
        outputUID = hardware.defaultUID(.output)
        inputUID = hardware.defaultUID(.input)
        if previousOutput != nil, previousOutput != outputUID { outputFollowsSystem = true; stopPlayback() }
        if previousInput != nil, previousInput != inputUID { inputFollowsSystem = true; discardRecording() }
        if (checking || requestingAccess), previousInput != inputUID || device(.input) == nil {
            stopCheck()
            failure = .inputChanged
        }
    }

    private func perform(_ operation: () throws -> Void) {
        guard enabled() else { return }
        failure = nil
        do { try operation() }
        catch { failure = (error as? SoundFailure) ?? .system(-1) }
        refresh()
    }

    func select(_ uid: String, direction: SoundDirection) {
        if uid.isEmpty {
            if direction == .input { inputFollowsSystem = true }
            else { outputFollowsSystem = true }
            refresh()
            return
        }
        perform { try hardware.select(uid, direction: direction) }
        if failure == nil {
            if direction == .input { inputFollowsSystem = false }
            else { outputFollowsSystem = false }
        }
    }

    func setVolume(_ value: Double, direction: SoundDirection, expectedUID: String? = nil) {
        guard enabled(), value.isFinite else { return }
        guard let device = device(direction), device.canChangeVolume,
              (expectedUID == nil || device.uid == expectedUID), hardware.defaultUID(direction) == device.uid else {
            failure = direction == .input ? .inputChanged : .system(-1)
            return
        }
        let target = min(1, max(0, value))
        if direction == .input, let i = inputs.firstIndex(where: { $0.uid == device.uid }) { inputs[i].volume = target }
        if direction == .output, let i = outputs.firstIndex(where: { $0.uid == device.uid }) { outputs[i].volume = target }
        failure = nil
        volumeRequests[direction] = (target, device.uid)
        guard volumeTasks[direction] == nil else { return }
        let token = (volumeGenerations[direction] ?? 0) + 1
        volumeGenerations[direction] = token
        volumeTasks[direction] = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(40)) } catch { break }
                guard let self, self.enabled(), self.windowOpen,
                      let request = self.volumeRequests.removeValue(forKey: direction) else { break }
                guard self.hardware.defaultUID(direction) == request.uid else {
                    self.failure = direction == .input ? .inputChanged : .system(-1)
                    self.refresh()
                    break
                }
                do {
                    if let core = self.hardware as? CoreSoundHardware {
                        try await core.setVolumeAsync(request.value, uid: request.uid, direction: direction)
                    } else {
                        try self.hardware.setVolume(request.value, uid: request.uid, direction: direction)
                    }
                } catch {
                    if self.volumeGenerations[direction] == token { self.failure = (error as? SoundFailure) ?? .system(-1) }
                }
                guard self.volumeGenerations[direction] == token, !Task.isCancelled else { return }
                if self.volumeRequests[direction] == nil { self.refresh(); break }
            }
            if let self, self.volumeGenerations[direction] == token { self.volumeTasks[direction] = nil }
        }
    }

    func toggleMute(_ direction: SoundDirection, expectedUID: String? = nil) {
        guard enabled() else { return }
        // SPEC: docs/spec.md — "Sound": hotkeys resolve the current default,
        // including when the window (and its listeners) is closed.
        refresh()
        guard expectedUID == nil || device(direction)?.uid == expectedUID else {
            failure = direction == .input ? .inputChanged : .system(-1)
            return
        }
        guard let device = device(direction) else { failure = .missingDevice; return }
        guard device.canMute, let muted = device.muted else { failure = .unsupported; return }
        perform { try hardware.setMute(!muted, uid: device.uid, direction: direction) }
        status?.refresh()
    }

    func startCheck() {
        guard windowOpen, enabled(), !checking, !requestingAccess, let uid = inputUID, device(.input) != nil else { return }
        discardRecording()
        failure = nil
        requestingAccess = true
        generation += 1
        let token = generation
        meter.requestAccess { [weak self] allowed in
            guard let self, self.generation == token, self.windowOpen, self.enabled() else { return }
            self.requestingAccess = false
            guard allowed else { self.failure = .permission; return }
            guard self.hardware.defaultUID(.input) == uid else { self.failure = .inputChanged; self.refresh(); return }
            do {
                try self.meter.start(uid) { [weak self] in
                    guard let self, self.generation == token, self.checking else { return }
                    self.stopCheck()
                    self.discardRecording()
                    self.failure = .inputChanged
                }
                self.checking = true
                self.ticker = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.checking, self.windowOpen, self.enabled() else { self?.stopCheck(); return }
                        guard self.meter.permitted else {
                            self.stopCheck()
                            self.discardRecording()
                            self.failure = .permission
                            return
                        }
                        let level = self.meter.level, peak = self.meter.peak
                        if abs(self.level - level) >= 0.01 { self.level = level }
                        if abs(self.peak - peak) >= 0.01 { self.peak = peak }
                        let duration = (self.meter.duration * 10).rounded(.down) / 10
                        if self.duration != duration { self.duration = duration }
                        if self.meter.duration >= SoundSampleBuffer.maximumDuration { self.stopCheck() }
                    }
                }
                self.ticker?.tolerance = 0.01
                if let ticker = self.ticker { RunLoop.main.add(ticker, forMode: .common) }
            } catch { self.stopCheck(); self.failure = (error as? SoundFailure) ?? .system(-1) }
        }
    }

    func stopCheck() {
        generation += 1
        ticker?.invalidate()
        ticker = nil
        meter.stop()
        checking = false
        requestingAccess = false
        level = 0
        peak = 0
        duration = meter.duration
        hasRecording = meter.hasRecording
    }

    func playRecording() {
        guard enabled(), windowOpen, hasRecording, !checking, !requestingAccess else { return }
        stopPlayback()
        failure = nil
        let token = playbackGeneration
        do {
            try meter.play { [weak self] in
                guard let self, self.playbackGeneration == token else { return }
                self.playing = false
            }
            playing = true
        } catch { failure = (error as? SoundFailure) ?? .system(-1) }
    }

    func stopPlayback() {
        playbackGeneration += 1
        meter.stopPlayback()
        playing = false
    }

    func discardRecording() {
        stopPlayback()
        meter.clearRecording()
        hasRecording = false
        duration = 0
    }

    func stageDemo(_ state: String = "idle") {
        outputs = [SoundDevice(uid: "speakers", name: "Mac speakers", volume: 0.65, muted: false, canChangeVolume: true, canMute: true),
                   SoundDevice(uid: "headphones", name: "Studio headphones", volume: 0.5, muted: false, canChangeVolume: true, canMute: true)]
        inputs = [SoundDevice(uid: "mic", name: "Mac microphone", volume: 0.75, muted: false, canChangeVolume: true, canMute: false)]
        outputUID = "speakers"
        inputUID = "mic"
        if state == "checking" { checking = true; level = 0.7; peak = 0.86; duration = 3.2 }
        if state == "recorded" { hasRecording = true; duration = 4.5 }
        if state == "muted" { outputs[0].muted = true; inputs[0].muted = true; inputs[0].canMute = true }
    }
}
