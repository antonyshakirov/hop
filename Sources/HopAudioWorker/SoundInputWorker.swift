import AVFoundation
import Foundation
import OSLog
import HopAudioDSP
import HopCore
import HopAudioEngine

private enum SoundFailure: Error { case missingDevice, unsupported, system(Int32) }

private final class SoundCapturedInput {
    let uid: String
    let channel: SoundAudioChannel
    private var engine = AVAudioEngine()
    private var observation: NSObjectProtocol?
    private var stopped = false
    private let settingsLock = NSLock()
    init(_ configuration: SoundInputConfiguration, failed: @escaping () -> Void) throws {
        uid = configuration.uid
        guard !uid.hasPrefix("com.antonshakirov.hop.audio."), let device = SoundHAL.device(uid) else { throw SoundFailure.missingDevice }
        channel = try SoundAudioChannel(rate: 48000)
        hop_audio_compensate_clock(channel.pointer)
        channel.configure(configuration.settings)
        var engine = self.engine
        var input = engine.inputNode
        if input.auAudioUnit.deviceID != device { try input.auAudioUnit.setDeviceID(device) }
        let hardwareFormat = input.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate >= 8000, hardwareFormat.channelCount > 0 else { throw SoundFailure.unsupported }
        let converter = SoundMicrophonePCMConverter()
        let report = SoundMicrophoneFormatReport()
        let channel = channel
        // Bluetooth can renegotiate between querying the node and installing
        // the tap. Let the hardware choose and convert each delivered PCM format.
        try SoundMicrophoneTapStartup.start(readFormat: { input.inputFormat(forBus: 0) }, installTap: {
            input.installTap(onBus: 0, bufferSize: 512, format: nil) { pcm, _ in
                if let buffer = converter.convert(pcm) {
                    report.converted(pcm.format)
                    _ = hop_audio_push(channel.pointer, buffer.audioBufferList, buffer.frameLength)
                }
            }
        }, removeTap: { input.removeTap(onBus: 0) }, stop: { engine.stop() }, rebuild: {
            guard let device = SoundHAL.device(configuration.uid) else { throw SoundFailure.missingDevice }
            let fresh = AVAudioEngine(), freshInput = fresh.inputNode
            if freshInput.auAudioUnit.deviceID != device { try freshInput.auAudioUnit.setDeviceID(device) }
            engine = fresh; input = freshInput
        }, start: { try engine.start() })
        self.engine = engine
        observation = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak engine] _ in
            if engine?.isRunning == false { failed() }
        }
    }
    func stop() {
        settingsLock.lock()
        guard !stopped else { settingsLock.unlock(); return }; stopped = true
        settingsLock.unlock()
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil; engine.inputNode.removeTap(onBus: 0); engine.stop()
    }
    deinit { stop() }
}

/// Called serially by one tap. Log format metadata only after conversion works.
private final class SoundMicrophoneFormatReport {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")
    private var previous: AVAudioFormat?
    func converted(_ format: AVAudioFormat) {
        guard previous?.isEqual(format) != true else { return }
        previous = format
        Self.log.notice("microphone-pcm-converted rate=\(format.sampleRate, privacy: .public) channels=\(format.channelCount, privacy: .public)")
    }
}

@available(macOS 14.2, *)
@MainActor
enum SoundInputWorker {
    static func run() -> Never {
        let worker = SoundWorkerEngine()
        do { try worker.prepare() }
        catch {
            let error = error as NSError
            worker.send(["failed": true, "reason": "prepare-failed", "errorDomain": error.domain, "errorCode": error.code])
            exit(1)
        }
        DispatchQueue(label: "Hop.Sound.Commands").async {
            while let line = readLine() {
                if line.utf8.count < 32768, let data = line.data(using: .utf8),
                   let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let muted = object["accessoryMute"] as? Bool,
                   let token = object["captureToken"] as? String, let request = object["muteRequest"] as? String {
                    DispatchQueue.main.async { worker.setMuted(muted, token: token, request: request) }
                    continue
                }
                guard line.utf8.count < 32768, let data = line.data(using: .utf8),
                      let command = try? JSONDecoder().decode(SoundWorkerCommand.self, from: data) else {
                    DispatchQueue.main.async { worker.silence(); worker.send(["failed": true]) }
                    continue
                }
                DispatchQueue.main.async { worker.apply(command) }
            }
            DispatchQueue.main.async { worker.stop(); exit(0) }
        }
        RunLoop.main.run()
        worker.stop(); exit(0)
    }
}

@available(macOS 14.2, *)
@MainActor
private final class SoundWorkerEngine {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")
    private let engine = AVAudioEngine()
    private let lifecycle = SoundInputWorkerLifecycle()
    private let gate = SoundInputMixGate()
    private var source: AVAudioSourceNode?
    private var inputs: [String: SoundCapturedInput] = [:]
    private var apps: [String: SoundCapturedApplication] = [:]
    private var appProcesses: [String: [UInt32]] = [:]
    private var microphoneToken: UUID?
    private var microphoneRoute: UUID?
    private var latestRequest: UInt64 = 0
    private var observation: NSObjectProtocol?

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let line = String(data: data, encoding: .utf8) else { return }
        print(line); fflush(stdout)
    }
    func prepare() throws {
        try SoundAccessoryMute.shared.install()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let gate = gate
        let source = AVAudioSourceNode(format: format) { _, _, frames, output in
            gate.render(output, frames: frames); return noErr
        }
        self.source = source; engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
        let generation = lifecycle.begin()
        observation = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lifecycle.configurationChanged(generation: generation, restart: {
                    try self.engine.start()
                }, silence: self.silence, failed: {
                    self.send(["failed": true, "reason": "output-configuration-changed"])
                })
            }
        }
        send(["ready": true])
    }
    func apply(_ command: SoundWorkerCommand) {
        if let id = command.requestID {
            guard id > latestRequest else { return }
            latestRequest = id
        }
        do {
            let selected = command.inputs.filter { $0.settings.active }
            let applications = (command.apps ?? []).filter { $0.settings.active }
            guard selected.count <= 32, applications.count <= 4,
                  Set(selected.map(\.uid)).count == selected.count,
                  Set(applications.map(\.id)).count == applications.count,
                  selected.allSatisfy({ SoundInputMixPreferences.allowsMicrophone($0.uid) }),
                  applications.allSatisfy({ SoundCallMixPolicy.allows($0.id) }) else { throw SoundFailure.unsupported }
            let nextToken = selected.isEmpty ? nil : (command.captureToken.flatMap(UUID.init(uuidString:)) ?? microphoneToken ?? UUID())
            let retainedMute = command.microphoneMuted == true || (nextToken != nil && gate.muted)
            if nextToken != microphoneToken { retireMicrophone() }
            let wantedInputs = Set(selected.map(\.uid))
            let wantedApps = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0.processes.sorted()) })
            let removedInputs = Set(inputs.keys).subtracting(wantedInputs)
            let removedApps = Set(apps.keys.filter { wantedApps[$0] == nil || wantedApps[$0] != appProcesses[$0] })
            func settings(_ value: SoundChannelSettings) -> SoundChannelSettings {
                var value = value; value.gain = min(1, value.safeGain); value.bass = false; return value
            }
            gate.replace(microphones: selected.compactMap { configuration in
                inputs[configuration.uid].map { ($0.channel, settings(configuration.settings)) }
            }, applications: applications.filter { !removedApps.contains($0.id) }.compactMap { apps[$0.id]?.channel },
                token: nextToken, muted: retainedMute)
            for uid in removedInputs { inputs.removeValue(forKey: uid)?.stop() }
            for id in removedApps { apps.removeValue(forKey: id)?.stop(); appProcesses[id] = nil }
            for configuration in selected where inputs[configuration.uid] == nil {
                Self.log.notice("microphone-starting")
                inputs[configuration.uid] = try SoundCapturedInput(configuration) { [weak self] in
                    MainActor.assumeIsolated { self?.silence(); self?.send(["failed": true]) }
                }
                Self.log.notice("microphone-started")
            }
            for configuration in applications where apps[configuration.id] == nil {
                apps[configuration.id] = try SoundCapturedApplication(configuration)
                appProcesses[configuration.id] = configuration.processes.sorted()
            }
            for configuration in applications { apps[configuration.id]?.channel.configure(settings(configuration.settings)) }
            gate.replace(microphones: selected.compactMap { configuration in
                inputs[configuration.uid].map { ($0.channel, settings(configuration.settings)) }
            }, applications: applications.compactMap { apps[$0.id]?.channel }, token: nextToken)
            if let token = nextToken, microphoneToken != token {
                let route = UUID(), gate = gate
                microphoneToken = token; microphoneRoute = route
                try SoundAccessoryMute.shared.bind(token, muted: gate.muted, apply: { value in
                    gate.setMuted(value, token: token)
                }, changed: { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.microphoneToken == token, self.microphoneRoute == route else { return }
                        self.send(["microphoneMuted": value, "captureToken": token.uuidString])
                    }
                })
            }
            if !engine.isRunning { try engine.start() }
            if let id = command.requestID {
                var reply: [String: Any] = ["applied": id, "captureCount": inputs.count + apps.count]
                if let token = microphoneToken {
                    reply["microphoneMuted"] = gate.muted; reply["captureToken"] = token.uuidString
                }
                send(reply)
            }
        } catch {
            silence()
            let error = error as NSError
            send(["failed": true, "reason": "configuration-failed", "errorDomain": error.domain, "errorCode": error.code])
        }
    }
    func setMuted(_ value: Bool, token: String, request: String) {
        let applied = microphoneToken?.uuidString == token && !inputs.isEmpty && SoundAccessoryMute.shared.setMuted(value)
        send(["muteApplied": applied, "muteRequest": request, "captureToken": token])
    }
    private func retireMicrophone() {
        microphoneRoute = nil
        if let token = microphoneToken { SoundAccessoryMute.shared.unbind(token) }
        microphoneToken = nil
    }
    func silence() {
        retireMicrophone()
        gate.replace(microphones: [], applications: [], token: nil)
        inputs.values.forEach { $0.stop() }; inputs.removeAll()
        apps.values.forEach { $0.stop() }; apps.removeAll(); appProcesses.removeAll()
    }
    func stop() {
        lifecycle.stop()
        silence()
        if let observation { NotificationCenter.default.removeObserver(observation) }; observation = nil
        engine.stop()
    }
}
