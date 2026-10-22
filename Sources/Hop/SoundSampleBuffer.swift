import AVFoundation
import HopCore

/// SPEC: docs/spec.md — "Sound": the microphone sample is bounded and stays in RAM.
final class SoundSampleBuffer: @unchecked Sendable {
    static let maximumDuration = 10.0
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var rms = 0.0
    private var peak = 0.0
    private var updated = ProcessInfo.processInfo.systemUptime

    init(format: AVAudioFormat) throws {
        guard format.sampleRate > 0, format.sampleRate <= 192_000,
              (1...8).contains(format.channelCount),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                                         channels: format.channelCount, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: output,
                   frameCapacity: AVAudioFrameCount(format.sampleRate * Self.maximumDuration)) else {
            throw SoundFailure.unsupported
        }
        self.buffer = buffer
    }

    func append(_ source: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard source.format.sampleRate == buffer.format.sampleRate,
              source.format.channelCount == buffer.format.channelCount,
              let input = source.floatChannelData, let output = buffer.floatChannelData,
              source.frameLength > 0 else { return }
        let frames = Int(source.frameLength), channels = Int(source.format.channelCount)
        let offset = Int(buffer.frameLength)
        let copyCount = min(frames, Int(buffer.frameCapacity) - offset)
        var sum = 0.0, maximum = 0.0
        for channel in 0..<channels {
            for frame in 0..<frames {
                let value = source.format.isInterleaved ? input[0][frame * channels + channel] : input[channel][frame]
                let sample = value.isFinite ? value : 0
                sum += Double(sample) * Double(sample)
                maximum = max(maximum, abs(Double(sample)))
                if frame < copyCount { output[channel][offset + frame] = sample }
            }
        }
        buffer.frameLength += AVAudioFrameCount(copyCount)
        rms = sqrt(sum / Double(frames * channels))
        peak = maximum
        updated = ProcessInfo.processInfo.systemUptime
    }

    var readings: (level: Double, peak: Double, duration: Double) {
        lock.lock(); defer { lock.unlock() }
        let fresh = ProcessInfo.processInfo.systemUptime - updated < 0.25
        return (fresh ? SoundLevel.normalized(rms: rms) : 0,
                fresh ? SoundLevel.normalized(rms: peak) : 0,
                Double(buffer.frameLength) / buffer.format.sampleRate)
    }

    /// Called after the capture engine and tap have stopped; no writer remains.
    func recorded() -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        return buffer.frameLength > 0 ? buffer : nil
    }
}
