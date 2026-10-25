import AVFoundation
import HopAudioDSP
import XCTest

final class SoundPlaybackGateTests: XCTestCase {
    func testGatedWarmupPrimesAndConsumesCaptureWithoutEmittingSamples() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_compensate_clock(channel)
        hop_audio_set_playback_enabled(channel, false)
        XCTAssertFalse(hop_audio_playback_ready(channel))
        let input = buffer(frames: 2048, value: 0.2), output = buffer(frames: 128, value: 1)
        XCTAssertEqual(hop_audio_push(channel, input.audioBufferList, input.frameLength), 2048)
        hop_audio_render(channel, output.mutableAudioBufferList, output.frameLength, false)
        XCTAssertTrue(hop_audio_playback_ready(channel))
        XCTAssertLessThan(hop_audio_queued(channel), 2048)
        XCTAssertTrue(samples(output).allSatisfy { $0 == 0 })
        hop_audio_set_playback_enabled(channel, true)
        hop_audio_render(channel, output.mutableAudioBufferList, output.frameLength, false)
        XCTAssertTrue(samples(output).allSatisfy { abs($0 - 0.2) < 0.000001 })
        hop_audio_discard_queued(channel)
        XCTAssertFalse(hop_audio_playback_ready(channel))
    }

    private func buffer(frames: AVAudioFrameCount, value: Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = value
            buffer.floatChannelData![1][index] = value
        }
        return buffer
    }
    private func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}
