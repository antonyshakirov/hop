import AVFoundation
import Combine
import Foundation
import HopCore
import HopAudioEngine

@MainActor
protocol SoundMeter: AnyObject {
    var muted: Bool { get }
    var muteChanged: ((Bool) -> Void)? { get set }
    func setMuted(_ value: Bool) -> Bool
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
    var muted: Bool { false }
    var muteChanged: ((Bool) -> Void)? { get { nil } set {} }
    func setMuted(_ value: Bool) -> Bool { false }
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
    private var muteToken: UUID?
    var muteChanged: ((Bool) -> Void)?
    var muted: Bool { SoundAccessoryMute.shared.gate.muted }
    func setMuted(_ value: Bool) -> Bool {
        guard engine != nil else { return false }
        return SoundAccessoryMute.shared.setMuted(value)
    }
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
        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate >= 8000, hardwareFormat.channelCount > 0 else { throw SoundFailure.missingDevice }
        let converter = SoundMicrophonePCMConverter()
        let samples = try SoundSampleBuffer(format: converter.outputFormat)
        self.samples = samples
        let token = UUID()
        try SoundAccessoryMute.shared.bind(token, muted: false, apply: { value in samples.setMuted(value); return true }, changed: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.muteToken == token else { return }
                self.muteChanged?(SoundAccessoryMute.shared.gate.muted)
            }
        })
        muteToken = token
        do {
            try SoundMicrophoneTapStartup.start(readFormat: { input.inputFormat(forBus: 0) }, installTap: {
                input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                    if let converted = converter.convert(buffer) { samples.append(converted) }
                }
            }, removeTap: { input.removeTap(onBus: 0) }, stop: { engine.stop() }, start: { try engine.start() })
        } catch { SoundAccessoryMute.shared.unbind(token); muteToken = nil; throw error }
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
        if let muteToken { SoundAccessoryMute.shared.unbind(muteToken) }
        muteToken = nil
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
    @Published private(set) var checkMuted = false
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
    private var observingInput = false
    private let hardware: SoundHardware
    private let meter: SoundMeter
    private let enabled: @MainActor () -> Bool
    private var ticker: Timer?
    private var generation = 0
    private var volumeTasks: [SoundDirection: Task<Void, Never>] = [:]
    private var volumeGenerations: [SoundDirection: Int] = [:]
    private struct VolumeRequest {
        var value: Double
        var uid: String
        var generation: Int
    }
    private struct VolumeAcknowledgement {
        var request: VolumeRequest
        var baseline: Double?
    }
    private static let volumeAcknowledgementTimeout: Duration = .milliseconds(500)
    private static let maximumVolumeAcknowledgementHistory = 128
    private var volumeRequests: [SoundDirection: VolumeRequest] = [:]
    private var volumeInFlight: [SoundDirection: VolumeRequest] = [:]
    private var volumeWorkerIDs: [SoundDirection: UUID] = [:]
    private var volumeAcknowledgements: [SoundDirection: VolumeAcknowledgement] = [:]
    private var volumeAcknowledgementHistory: [SoundDirection: [VolumeRequest]] = [:]
    private var volumeAcknowledgementTasks: [SoundDirection: Task<Void, Never>] = [:]
    private var observedVolumes: [SoundDirection: (uid: String, value: Double?)] = [:]
    private var outputRefreshTask: Task<Void, Never>?
    private var outputRefreshID: UUID?
    private var playbackGeneration = 0
    private let status: SoundMuteStatus?

    init(hardware: SoundHardware? = nil, meter: SoundMeter? = nil,
         enabled: (@MainActor () -> Bool)? = nil, status: SoundMuteStatus? = nil) {
        self.status = status
        self.hardware = hardware ?? CoreSoundHardware()
        self.meter = meter ?? MicrophoneLevelMeter()
        self.enabled = enabled ?? { ModuleActivation.isOn("sound") }
        self.meter.muteChanged = { [weak self] value in self?.checkMuted = value }
    }

    func device(_ direction: SoundDirection) -> SoundDevice? {
        let uid = direction == .output ? outputUID : inputUID
        return (direction == .output ? outputs : inputs).first { $0.uid == uid }
    }

    func open() {
        guard enabled(), !windowOpen else { return }
        windowOpen = true
        refresh()
        watchHardware()
    }

    func beginInputObservation() {
        guard enabled(), !observingInput else { return }
        observingInput = true
        refresh()
        watchHardware()
    }

    func endInputObservation() {
        observingInput = false
        if !windowOpen { hardware.unwatch() }
    }

    private func watchHardware() {
        hardware.watch({ [weak self] in self?.refresh() },
                       outputVolumeChanged: { [weak self] in self?.scheduleOutputRefresh() })
    }

    func closeControls(_ direction: SoundDirection) {
        if direction == .input { stopCheck(); discardRecording() }
        cancelVolume(direction)
    }
    private func cancelAcknowledgement(_ direction: SoundDirection, clearHistory: Bool = true) {
        volumeAcknowledgements[direction] = nil
        if clearHistory { volumeAcknowledgementHistory[direction] = nil }
        volumeAcknowledgementTasks.removeValue(forKey: direction)?.cancel()
    }
    // SPEC: docs/spec.md — "Physical device volume dispatch": retain writer ownership until its physical operation returns.
    private func cancelVolume(_ direction: SoundDirection) {
        volumeTasks[direction]?.cancel()
        volumeRequests[direction] = nil; volumeInFlight[direction] = nil
        volumeGenerations[direction, default: 0] += 1
        cancelAcknowledgement(direction)
    }
    private func scheduleOutputRefresh() {
        guard windowOpen, outputRefreshTask == nil else { return }
        let id = UUID(); outputRefreshID = id
        outputRefreshTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.windowOpen, self.outputRefreshID == id else { return }
            self.outputRefreshTask = nil; self.outputRefreshID = nil
            self.refresh()
        }
    }

    func close() {
        windowOpen = false
        outputRefreshTask?.cancel(); outputRefreshTask = nil; outputRefreshID = nil
        for direction in SoundDirection.allCases { closeControls(direction) }
        if !observingInput { hardware.unwatch() }
        failure = nil
    }

    func refresh() {
        guard enabled() else { close(); return }
        let previousInput = inputUID, previousOutput = outputUID
        let nextOutputs = hardware.devices(.output), nextInputs = hardware.devices(.input)
        outputUID = hardware.defaultUID(.output)
        inputUID = hardware.defaultUID(.input)
        if previousOutput != nil, previousOutput != outputUID { cancelVolume(.output) }
        if previousInput != nil, previousInput != inputUID { cancelVolume(.input) }
        outputs = reflectingVolume(nextOutputs, direction: .output, uid: outputUID)
        inputs = reflectingVolume(nextInputs, direction: .input, uid: inputUID)
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

    private func reflectingVolume(_ devices: [SoundDevice], direction: SoundDirection, uid: String?) -> [SoundDevice] {
        guard let uid, let index = devices.firstIndex(where: { $0.uid == uid }) else {
            observedVolumes[direction] = nil
            return devices
        }
        let actual = devices[index].volume
        observedVolumes[direction] = (uid, actual)
        if let acknowledgement = volumeAcknowledgements[direction], let actual {
            let matchesTarget = abs(actual - acknowledgement.request.value) < 0.0001
            let changed = acknowledgement.baseline.map { abs(actual - $0) >= 0.0001 } ?? true
            let superseded = volumeAcknowledgementHistory[direction]?.contains {
                $0.uid == uid && $0.generation < acknowledgement.request.generation && abs(actual - $0.value) < 0.0001
            } == true
            if matchesTarget || (changed && !superseded) { cancelAcknowledgement(direction) }
        }
        let request = volumeRequests[direction] ?? volumeInFlight[direction] ?? volumeAcknowledgements[direction]?.request
        guard let request, request.uid == uid, request.generation == volumeGenerations[direction] else { return devices }
        var result = devices; result[index].volume = request.value
        return result
    }
    func setVolume(_ value: Double, direction: SoundDirection, expectedUID: String? = nil) {
        guard enabled(), windowOpen, value.isFinite else { return }
        guard let device = device(direction), device.canChangeVolume,
              (expectedUID == nil || device.uid == expectedUID), hardware.defaultUID(direction) == device.uid else {
            failure = direction == .input ? .inputChanged : .system(-1)
            return
        }
        let target = min(1, max(0, value))
        if direction == .input, let i = inputs.firstIndex(where: { $0.uid == device.uid }) { inputs[i].volume = target }
        if direction == .output, let i = outputs.firstIndex(where: { $0.uid == device.uid }) { outputs[i].volume = target }
        failure = nil; cancelAcknowledgement(direction, clearHistory: false)
        let volumeGeneration = (volumeGenerations[direction] ?? 0) + 1
        volumeGenerations[direction] = volumeGeneration
        volumeRequests[direction] = VolumeRequest(value: target, uid: device.uid, generation: volumeGeneration)
        sendVolumeRequests(direction)
    }
    // SPEC: docs/spec.md — "Physical device volume dispatch": superseded readbacks cannot rewind the latest target.
    private func recordVolumeWrite(_ request: VolumeRequest, direction: SoundDirection) {
        var history = volumeAcknowledgementHistory[direction] ?? []
        history.append(request)
        if history.count > Self.maximumVolumeAcknowledgementHistory {
            history.removeFirst(history.count - Self.maximumVolumeAcknowledgementHistory)
        }
        volumeAcknowledgementHistory[direction] = history
    }
    private func awaitVolumeAcknowledgement(_ request: VolumeRequest, direction: SoundDirection) {
        cancelAcknowledgement(direction, clearHistory: false)
        let baseline = observedVolumes[direction].flatMap { $0.uid == request.uid ? $0.value : nil }
        volumeAcknowledgements[direction] = VolumeAcknowledgement(request: request, baseline: baseline)
        volumeAcknowledgementTasks[direction] = Task { [weak self] in
            do { try await Task.sleep(for: Self.volumeAcknowledgementTimeout) } catch { return }
            guard let self, !Task.isCancelled, self.windowOpen,
                  self.volumeAcknowledgements[direction]?.request.generation == request.generation else { return }
            self.volumeAcknowledgements[direction] = nil; self.volumeAcknowledgementTasks[direction] = nil
            self.volumeAcknowledgementHistory[direction] = nil
            self.refresh()
        }
    }
    // SPEC: docs/spec.md — "Physical device volume dispatch": immediate dispatch with one latest pending value per direction.
    private func sendVolumeRequests(_ direction: SoundDirection) {
        guard volumeTasks[direction] == nil, volumeRequests[direction] != nil else { return }
        let workerID = UUID(); volumeWorkerIDs[direction] = workerID
        volumeTasks[direction] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.volumeWorkerIDs[direction] == workerID {
                    self.volumeWorkerIDs[direction] = nil; self.volumeTasks[direction] = nil
                    if self.enabled(), self.windowOpen { self.sendVolumeRequests(direction) }
                }
            }
            while !Task.isCancelled {
                guard self.enabled(), self.windowOpen,
                      let request = self.volumeRequests.removeValue(forKey: direction) else { break }
                guard request.generation == self.volumeGenerations[direction],
                      self.hardware.defaultUID(direction) == request.uid else {
                    self.failure = direction == .input ? .inputChanged : .system(-1)
                    self.refresh(); break
                }
                self.volumeInFlight[direction] = request
                do {
                    try await self.hardware.setVolumeAsync(request.value, uid: request.uid, direction: direction)
                    if !Task.isCancelled, self.windowOpen, self.enabled() {
                        self.recordVolumeWrite(request, direction: direction)
                        if request.generation == self.volumeGenerations[direction] {
                            self.awaitVolumeAcknowledgement(request, direction: direction)
                        }
                    }
                } catch {
                    if !Task.isCancelled, request.generation == self.volumeGenerations[direction] {
                        self.cancelAcknowledgement(direction)
                        self.failure = (error as? SoundFailure) ?? .system(-1)
                    }
                }
                self.volumeInFlight[direction] = nil
                guard !Task.isCancelled else { break }
                if self.volumeRequests[direction] == nil { self.refresh(); break }
            }
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

    func toggleCheckMute() {
        guard checking, windowOpen, enabled() else { return }
        if !meter.setMuted(!checkMuted) { failure = .unsupported }
        checkMuted = meter.muted
    }

    func stopCheck() {
        generation += 1
        ticker?.invalidate()
        ticker = nil
        meter.stop()
        checking = false
        checkMuted = false
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
        if state == "empty-input" { inputs = []; inputUID = nil }
        if state == "checking" { checking = true; level = 0.7; peak = 0.86; duration = 3.2 }
        if state == "recorded" { hasRecording = true; duration = 4.5 }
        if state == "muted" { outputs[0].muted = true; inputs[0].muted = true; inputs[0].canMute = true }
    }
}
