import AVFoundation
import HopAudioDSP
import XCTest

final class SoundOutputStartupGainTests: XCTestCase {
    func testFirstPlaybackFrameUsesSavedGainWithoutUnityBurst() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 0.25, false, false)
        let samples = render(channel, value: 0.2)
        XCTAssertTrue(samples.allSatisfy { abs($0 - 0.05) < 0.000001 },
                      "A 25% preset must apply from the first rendered sample")
    }

    func testEmptyPrerollDoesNotInitializeGainBeforeFirstCapturedFrame() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        output.frameLength = 128
        hop_audio_render(channel, output.mutableAudioBufferList, output.frameLength, false)
        hop_audio_configure(channel, 0.25, false, false)
        XCTAssertEqual(render(channel, value: 0.2)[0], 0.05, accuracy: 0.000001)
    }

    func testLatestPresetBeforeOpeningWarmupGateAppliesToFirstAudibleSample() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_set_playback_enabled(channel, false)
        hop_audio_configure(channel, 1, false, false)
        XCTAssertTrue(render(channel, value: 0.2).allSatisfy { $0 == 0 })
        hop_audio_configure(channel, 0.25, false, false)
        hop_audio_set_playback_enabled(channel, true)
        XCTAssertEqual(render(channel, value: 0.2)[0], 0.05, accuracy: 0.000001)
    }

    func testLatestGainBeforeFirstPlaybackFrameWins() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 0.75, false, false)
        hop_audio_configure(channel, 0.1, false, false)
        XCTAssertEqual(render(channel, value: 0.2)[0], 0.02, accuracy: 0.000001)
    }

    func testLaterGainChangesKeepExistingSmoothing() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 1, false, false)
        XCTAssertEqual(render(channel, value: 0.2)[0], 0.2, accuracy: 0.000001)
        hop_audio_configure(channel, 0.25, false, false)
        let samples = render(channel, value: 0.2)
        XCTAssertGreaterThan(samples[0], 0.05)
        XCTAssertLessThan(samples[0], 0.2)
        XCTAssertLessThan(samples.last!, samples[0])
    }

    func testMutedPresetHasNoStartupSamples() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 0.25, true, false)
        XCTAssertTrue(render(channel, value: 0.2).allSatisfy { $0 == 0 })
    }

    private func render(_ channel: OpaquePointer, value: Float) -> [Float] {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        input.frameLength = 128; output.frameLength = 128
        for index in 0..<128 {
            input.floatChannelData![0][index] = value
            input.floatChannelData![1][index] = value
        }
        XCTAssertEqual(hop_audio_push(channel, input.audioBufferList, input.frameLength), 128)
        hop_audio_render(channel, output.mutableAudioBufferList, output.frameLength, false)
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: 128))
    }
}
