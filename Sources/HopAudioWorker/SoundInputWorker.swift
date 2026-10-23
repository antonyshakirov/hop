import AVFoundation
import Foundation
import HopAudioDSP
import HopCore
import HopAudioEngine

private enum SoundFailure: Error { case missingDevice, unsupported, system(Int32) }

private final class SoundCapturedInput {
    let uid: String
    let channel: SoundAudioChannel
    private let engine = AVAudioEngine()
    private var observation: NSObjectProtocol?
    private var stopped = false
    init(_ configuration: SoundInputConfiguration, failed: @escaping () -> Void) throws {
        uid = configuration.uid
        guard !uid.hasPrefix("com.antonshakirov.hop.audio."), let device = SoundHAL.device(uid) else { throw SoundFailure.missingDevice }
        channel = try SoundAudioChannel(rate: 48000)
        hop_audio_compensate_clock(channel.pointer)
        channel.configure(configuration.settings)
        let input = engine.inputNode
        if input.auAudioUnit.deviceID != device { try input.auAudioUnit.setDeviceID(device) }
        let source = input.outputFormat(forBus: 0)
        let destination = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        guard source.sampleRate >= 8000, source.channelCount > 0,
              let converter = AVAudioConverter(from: source, to: destination),
              let buffer = AVAudioPCMBuffer(pcmFormat: destination, frameCapacity: 8192) else { throw SoundFailure.unsupported }
        let channel = channel
        input.installTap(onBus: 0, bufferSize: 512, format: source) { pcm, _ in
            var supplied = false
            var error: NSError?
            let result = converter.convert(to: buffer, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return pcm
            }
            if result != .error, buffer.frameLength > 0 {
                _ = hop_audio_push(channel.pointer, buffer.audioBufferList, buffer.frameLength)
            }
        }
        do { try engine.start() }
        catch { input.removeTap(onBus: 0); engine.stop(); throw error }
        observation = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak engine] _ in
            if engine?.isRunning == false { failed() }
        }
    }
    func stop() {
        guard !stopped else { return }; stopped = true
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil; engine.inputNode.removeTap(onBus: 0); engine.stop()
    }
    deinit { stop() }
}

private final class SoundMixGate: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [SoundAudioChannel] = []
    func replace(_ value: [SoundAudioChannel]) { lock.lock(); channels = value; lock.unlock() }
    func render(_ output: UnsafeMutablePointer<AudioBufferList>, frames: UInt32) {
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard lock.try() else { return }
        let current = channels
        lock.unlock()
        for channel in current { hop_audio_render(channel.pointer, output, frames, true) }
        hop_audio_limit(output, frames)
    }
}

@available(macOS 14.2, *)
@MainActor
enum SoundInputWorker {
    static func run() -> Never {
        let worker = SoundWorkerEngine()
        do { try worker.prepare() } catch { exit(1) }
        DispatchQueue(label: "Hop.Sound.Commands").async {
            while let line = readLine() {
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
    private let engine = AVAudioEngine()
    private let gate = SoundMixGate()
    private var source: AVAudioSourceNode?
    private var inputs: [String: SoundCapturedInput] = [:]
    private var apps: [String: SoundCapturedApplication] = [:]
    private var appProcesses: [String: [UInt32]] = [:]
    private var latestRequest: UInt64 = 0
    private var observation: NSObjectProtocol?

    func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let line = String(data: data, encoding: .utf8) else { return }
        print(line); fflush(stdout)
    }
    func prepare() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let gate = gate
        let source = AVAudioSourceNode(format: format) { _, _, frames, output in
            gate.render(output, frames: frames); return noErr
        }
        self.source = source; engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
        observation = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.silence()
                do { try self.engine.start() } catch {}
                self.send(["failed": true, "reason": "output-configuration-changed"])
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
            guard selected.count <= 1, applications.count <= 4,
                  Set(selected.map(\.uid)).count == selected.count,
                  Set(applications.map(\.id)).count == applications.count,
                  applications.allSatisfy({ SoundCallMixPolicy.allows($0.id) }) else { throw SoundFailure.unsupported }
            let changed = Set(selected.map(\.uid)) != Set(inputs.keys) || Set(applications.map(\.id)) != Set(apps.keys)
                || applications.contains { appProcesses[$0.id] != $0.processes }
            if changed {
                gate.replace([])
                inputs.values.forEach { $0.stop() }; inputs.removeAll()
                apps.values.forEach { $0.stop() }; apps.removeAll(); appProcesses.removeAll()
                for configuration in selected {
                    inputs[configuration.uid] = try SoundCapturedInput(configuration) { [weak self] in
                        MainActor.assumeIsolated { self?.silence(); self?.send(["failed": true]) }
                    }
                }
                for configuration in applications {
                    apps[configuration.id] = try SoundCapturedApplication(configuration)
                    appProcesses[configuration.id] = configuration.processes
                }
            }
            func settings(_ value: SoundChannelSettings) -> SoundChannelSettings {
                var value = value; value.gain = min(1, value.safeGain); value.bass = false; return value
            }
            for configuration in selected { inputs[configuration.uid]?.channel.configure(settings(configuration.settings)) }
            for configuration in applications { apps[configuration.id]?.channel.configure(settings(configuration.settings)) }
            gate.replace(selected.compactMap { inputs[$0.uid]?.channel } + applications.compactMap { apps[$0.id]?.channel })
            if !engine.isRunning { try engine.start() }
            if let id = command.requestID { send(["applied": id, "captureCount": inputs.count + apps.count]) }
        } catch { silence(); send(["failed": true, "reason": String(describing: error)]) }
    }
    func silence() {
        gate.replace([])
        inputs.values.forEach { $0.stop() }; inputs.removeAll()
        apps.values.forEach { $0.stop() }; apps.removeAll(); appProcesses.removeAll()
    }
    func stop() {
        silence()
        if let observation { NotificationCenter.default.removeObserver(observation) }; observation = nil
        engine.stop()
    }
}
