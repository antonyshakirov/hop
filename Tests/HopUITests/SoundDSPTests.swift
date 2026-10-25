import AVFoundation
import HopAudioDSP
import HopAudioEngine
import HopCore
import XCTest

final class SoundDSPTests: XCTestCase {
    func testLegacyNoiseSuppressionSettingsCannotRemoveAnySamples() throws {
        let data = Data(#"{"gain":1,"muted":false,"denoise":true,"bass":false,"active":true}"#.utf8)
        let settings = try JSONDecoder().decode(SoundChannelSettings.self, from: data)
        let channel = try SoundAudioChannel(rate: 48000)
        channel.configure(settings)
        let input = (0..<4096).map { Float(sin(Double($0) * 0.37)) * 0.02 }
        let output = render(channel.pointer, input)
        XCTAssertTrue(zip(input, output).allSatisfy { $0 == $1 }, "Legacy noise-suppression settings must leave every sample unchanged at unity gain")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        XCTAssertNil(encoded["denoise"])
    }
    func testApplicationActivityIsMeasuredBeforeListeningMuteAndGain() throws {
        let channel = try SoundAudioChannel(rate: 48000)
        var settings = SoundChannelSettings(); settings.gain = 0; settings.muted = true
        channel.configure(settings)
        XCTAssertTrue(render(channel.pointer, Array(repeating: 0.3, count: 1024)).allSatisfy { $0 == 0 })
        XCTAssertEqual(hop_audio_source_peak(channel.pointer), 0.3, accuracy: 0.0001)
        _ = render(channel.pointer, Array(repeating: 0, count: 1024))
        XCTAssertEqual(hop_audio_source_peak(channel.pointer), 0)
    }
    func testSourceActivityRefreshesWhenPlaybackPausedAndRingFull() throws {
        let channel = try SoundAudioChannel(rate: 48000)
        let full = buffer(Array(repeating: 0.2, count: 8192))
        XCTAssertEqual(hop_audio_push(channel.pointer, full.audioBufferList, full.frameLength), 8192)
        let silence = buffer(Array(repeating: 0, count: 32))
        XCTAssertEqual(hop_audio_push(channel.pointer, silence.audioBufferList, silence.frameLength), 0)
        XCTAssertEqual(hop_audio_source_peak(channel.pointer), 0)
    }
    func testRerouteDiscardsAudioQueuedForPreviousOutput() throws {
        let channel = try SoundAudioChannel(rate: 48000)
        let old = buffer(Array(repeating: 0.2, count: 1024))
        _ = hop_audio_push(channel.pointer, old.audioBufferList, old.frameLength)
        hop_audio_discard_queued(channel.pointer)
        XCTAssertEqual(hop_audio_queued(channel.pointer), 0)
        let fresh = render(channel.pointer, Array(repeating: 0.4, count: 1024))
        XCTAssertEqual(fresh.first!, 0.4, accuracy: 0.0001)
    }
    func testRerouteClearsFilterTailBeforeSilentDestination() throws {
        let channel = try SoundAudioChannel(rate: 48000)
        hop_audio_configure(channel.pointer, 1, false, true)
        _ = render(channel.pointer, Array(repeating: 0.3, count: 1024))
        hop_audio_discard_queued(channel.pointer)
        XCTAssertTrue(render(channel.pointer, Array(repeating: 0, count: 1024)).allSatisfy { $0 == 0 })
    }
    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        for c in 0..<2 { for i in samples.indices { buffer.floatChannelData![c][i] = samples[i] } }
        return buffer
    }
    private func render(_ channel: OpaquePointer, _ samples: [Float]) -> [Float] {
        let input = buffer(samples), output = buffer(samples.map { _ in 0 })
        XCTAssertEqual(hop_audio_push(channel, input.audioBufferList, input.frameLength), input.frameLength)
        hop_audio_render(channel, output.mutableAudioBufferList, output.frameLength, false)
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: samples.count))
    }
    func testSoftwareGainDoublesQuietAudioAndMutePreservesGain() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 2, false, false)
        XCTAssertEqual(render(channel, Array(repeating: 0.2, count: 4096)).last!, 0.4, accuracy: 0.0001)
        hop_audio_configure(channel, 2, true, false)
        XCTAssertTrue(render(channel, Array(repeating: 0.2, count: 4096)).allSatisfy { $0 == 0 })
        hop_audio_configure(channel, 2, false, false)
        XCTAssertEqual(render(channel, Array(repeating: 0.2, count: 4096)).last!, 0.4, accuracy: 0.0001)
    }
    func testLimiterAndInvalidSamplesRemainFiniteAndWithinFullScale() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 2, false, false)
        let output = render(channel, Array(repeating: 4, count: 2048) + [.nan, .infinity, -.infinity])
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertEqual(Array(output.suffix(3)), [0, 0, 0])
    }
    func testMutedStartupEmitsNoSampleBeforeFirstUnmute() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 2, true, true)
        XCTAssertTrue(render(channel, Array(repeating: 0.7, count: 1024)).allSatisfy { $0 == 0 })
        XCTAssertEqual(hop_audio_peak(channel), 0)
    }
    func testRingOverflowDropsIncomingBlockWithoutOverwritingUnreadAudio() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        let full = buffer(Array(repeating: 0.2, count: 8192)), extra = buffer([0.6])
        XCTAssertEqual(hop_audio_push(channel, full.audioBufferList, full.frameLength), 8192)
        XCTAssertEqual(hop_audio_push(channel, extra.audioBufferList, extra.frameLength), 0)
        let output = buffer(Array(repeating: 0, count: 8192))
        hop_audio_render(channel, output.mutableAudioBufferList, output.frameLength, false)
        XCTAssertEqual(output.floatChannelData![0][8191], 0.2, accuracy: 0.0001)
        XCTAssertEqual(render(channel, [0.6])[0], 0.6, accuracy: 0.0001)
    }
    func testBassShelfBoostsLowFrequenciesMoreThanHighFrequencies() {
        func rms(_ frequency: Double, bass: Bool) -> Double {
            let channel = hop_audio_create(48000)!
            defer { hop_audio_destroy(channel) }
            hop_audio_configure(channel, 1, false, bass)
            let input = (0..<8192).map { Float(sin(Double($0) * 2 * .pi * frequency / 48000)) * 0.1 }
            let output = render(channel, input).suffix(4096)
            return sqrt(output.reduce(0) { $0 + Double($1 * $1) } / 4096)
        }
        let low = rms(80, bass: true) / rms(80, bass: false)
        let high = rms(2000, bass: true) / rms(2000, bass: false)
        XCTAssertGreaterThan(low, 1.7)
        XCTAssertLessThan(high, 1.1)
    }
    func testChannelConfigurationRoundTripsAndClampsInvalidGain() throws {
        var settings = SoundChannelSettings()
        settings.gain = 4; settings.bass = true
        XCTAssertEqual(settings.safeGain, 2)
        let command = SoundWorkerCommand(start: true, meters: false, inputs: [.init(uid: "test", settings: settings)])
        let read = try JSONDecoder().decode(SoundWorkerCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(read.inputs[0].settings, settings)
        settings.gain = .nan
        XCTAssertEqual(settings.safeGain, 1)
    }
    func testIndependentInputClocksStayBoundedWithoutDroppedBlocksOrGaps() {
        for count in [479, 481] {
            let channel = hop_audio_create(48000)!
            hop_audio_compensate_clock(channel)
            let input = buffer(Array(repeating: 0.2, count: count)), output = buffer(Array(repeating: 0, count: 480))
            for block in 0..<2400 {
                XCTAssertEqual(hop_audio_push(channel, input.audioBufferList, input.frameLength), UInt32(count))
                hop_audio_render(channel, output.mutableAudioBufferList, 480, false)
                XCTAssertLessThan(hop_audio_queued(channel), 3000)
                if block > 20 {
                    XCTAssertTrue(UnsafeBufferPointer(start: output.floatChannelData![0], count: 480).allSatisfy { abs($0 - 0.2) < 0.0001 })
                }
            }
            hop_audio_destroy(channel)
        }
    }
    func testAccessoryMuteZerosMicrophoneWithoutMutingApplicationAudio() throws {
        let microphone = try SoundAudioChannel(rate: 48000), application = try SoundAudioChannel(rate: 48000)
        var microphoneSettings = SoundChannelSettings()
        microphone.configure(microphoneSettings); application.configure(.init())
        let gate = SoundAccessoryMuteGate()
        gate.bind(UUID(), muted: false, apply: { value in
            microphoneSettings.muted = value; microphone.configure(microphoneSettings); return true
        }, changed: { _ in })
        let voice = Array(repeating: Float(0.2), count: 4096), music = Array(repeating: Float(0.1), count: 4096)
        XCTAssertEqual(render(microphone.pointer, voice).last!, 0.2, accuracy: 0.0001)
        XCTAssertTrue(gate.request(true))
        XCTAssertTrue(render(microphone.pointer, voice).allSatisfy { $0 == 0 })
        XCTAssertTrue(render(application.pointer, music).allSatisfy { abs($0 - 0.1) < 0.0001 })
        XCTAssertTrue(gate.request(false))
        XCTAssertEqual(render(microphone.pointer, voice).last!, 0.2, accuracy: 0.0001)
    }

}
