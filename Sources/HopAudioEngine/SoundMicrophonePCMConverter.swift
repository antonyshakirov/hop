import AVFoundation

/// Converts one microphone tap's buffers to Hop's 48 kHz stereo mix format.
/// The output buffer is reused; consume it before converting the next input.
public final class SoundMicrophonePCMConverter {
    public let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    private var converter: AVAudioConverter?
    private var buffer: AVAudioPCMBuffer?

    public init() {}

    public func convert(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = pcm.format
        guard pcm.frameLength > 0, format.sampleRate.isFinite, format.sampleRate >= 8000,
              (1...32).contains(format.channelCount) else { return nil }
        let required = ceil(Double(pcm.frameLength) * outputFormat.sampleRate / format.sampleRate) + 32
        guard required <= 131072 else { return nil }
        if converter?.inputFormat.isEqual(format) != true {
            converter = AVAudioConverter(from: format, to: outputFormat)
        }
        if buffer == nil || Double(buffer!.frameCapacity) < required {
            buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(required))
        }
        guard let converter, let buffer else { return nil }
        buffer.frameLength = 0
        var supplied = false
        var error: NSError?
        let result = converter.convert(to: buffer, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return pcm
        }
        return result != .error && buffer.frameLength > 0 ? buffer : nil
    }
}
