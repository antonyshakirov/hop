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
        if source.channelCount == 1 { hop_audio_mono_voice(channel.pointer) }
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

@MainActor
enum SoundInputWorker {
    static func run() -> Never {
        let worker = SoundWorkerEngine()
        do { try worker.prepare() } catch { exit(1) }
        DispatchQueue(label: "Hop.Sound.Commands").async {
            while let line = readLine() {
                guard line.utf8.count < 32768, let data = line.data(using: .utf8),
                      let command = try? JSONDecoder().decode(SoundWorkerCommand.self, from: data) else { continue }
                DispatchQueue.main.async { worker.apply(command) }
            }
            DispatchQueue.main.async { worker.stop(); exit(0) }
        }
        RunLoop.main.run()
        worker.stop(); exit(0)
    }
}

@MainActor
private final class SoundWorkerEngine {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var inputs: [String: SoundCapturedInput] = [:]
    private var meters: Timer?
    private var observation: NSObjectProtocol?
    private var latest: SoundWorkerCommand?

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let line = String(data: data, encoding: .utf8) else { return }
        print(line); fflush(stdout)
    }
    func prepare() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let source = AVAudioSourceNode(format: format) { _, _, _, output in
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
        self.source = source; engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        send(["ready": true])
    }
    func apply(_ command: SoundWorkerCommand) {
        latest = command
        do {
            let selected = command.inputs.filter { $0.settings.active }
            guard selected.count <= 16, Set(selected.map(\.uid)).count == selected.count else { throw SoundFailure.unsupported }
            let changed = Set(selected.map(\.uid)) != Set(inputs.keys)
            if changed {
                engine.stop()
                if let source { engine.detach(source) }
                for uid in Array(inputs.keys) where !selected.contains(where: { $0.uid == uid }) { inputs.removeValue(forKey: uid)?.stop() }
                for configuration in selected where inputs[configuration.uid] == nil {
                    inputs[configuration.uid] = try SoundCapturedInput(configuration) { [weak self] in
                        MainActor.assumeIsolated { self?.rebuild(configuration.uid) }
                    }
                }
                let channels = selected.compactMap { inputs[$0.uid]?.channel }
                let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
                let source = AVAudioSourceNode(format: format) { _, _, frames, output in
                    for buffer in UnsafeMutableAudioBufferListPointer(output) {
                        if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                    }
                    for channel in channels { hop_audio_render(channel.pointer, output, frames, true) }
                    hop_audio_limit(output, frames); return noErr
                }
                self.source = source; engine.attach(source); engine.connect(source, to: engine.mainMixerNode, format: format)
            }
            for configuration in selected { inputs[configuration.uid]?.channel.configure(configuration.settings) }
            if command.start || changed { try engine.start(); send(["started": true]) }
            meters?.invalidate(); meters = nil
            if command.meters {
                let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.send(["levels": self.inputs.mapValues { Double(hop_audio_peak($0.channel.pointer)) }])
                    }
                }
                meters = timer; RunLoop.main.add(timer, forMode: .common)
            }
            if observation == nil {
                observation = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self, weak engine] _ in
                    MainActor.assumeIsolated {
                        if let engine, !engine.isRunning {
                            do { try engine.start() } catch { self?.stop(); self?.send(["failed": true]) }
                        }
                    }
                }
            }
        } catch { stop(); send(["failed": true]) }
    }
    private func rebuild(_ uid: String) {
        guard let latest, inputs[uid] != nil else { return }
        engine.stop()
        inputs.removeValue(forKey: uid)?.stop()
        apply(latest)
    }
    func stop() {
        if let observation { NotificationCenter.default.removeObserver(observation) }
        observation = nil; meters?.invalidate(); meters = nil; latest = nil
        engine.stop(); inputs.values.forEach { $0.stop() }; inputs.removeAll()
    }
}
