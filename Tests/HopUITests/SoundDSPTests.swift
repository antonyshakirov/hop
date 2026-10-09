import AVFoundation
import HopAudioDSP
import HopCore
import XCTest

final class SoundDSPTests: XCTestCase {
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
        hop_audio_configure(channel, 2, false, false, false)
        XCTAssertEqual(render(channel, Array(repeating: 0.2, count: 4096)).last!, 0.4, accuracy: 0.0001)
        hop_audio_configure(channel, 2, true, false, false)
        XCTAssertTrue(render(channel, Array(repeating: 0.2, count: 4096)).allSatisfy { $0 == 0 })
        hop_audio_configure(channel, 2, false, false, false)
        XCTAssertEqual(render(channel, Array(repeating: 0.2, count: 4096)).last!, 0.4, accuracy: 0.0001)
    }
    func testLimiterAndInvalidSamplesRemainFiniteAndWithinFullScale() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 2, false, false, false)
        let output = render(channel, Array(repeating: 4, count: 2048) + [.nan, .infinity, -.infinity])
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertEqual(Array(output.suffix(3)), [0, 0, 0])
    }
    func testMutedStartupEmitsNoSampleBeforeFirstUnmute() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 2, true, false, true)
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
            hop_audio_configure(channel, 1, false, false, bass)
            let input = (0..<8192).map { Float(sin(Double($0) * 2 * .pi * frequency / 48000)) * 0.1 }
            let output = render(channel, input).suffix(4096)
            return sqrt(output.reduce(0) { $0 + Double($1 * $1) } / 4096)
        }
        let low = rms(80, bass: true) / rms(80, bass: false)
        let high = rms(2000, bass: true) / rms(2000, bass: false)
        XCTAssertGreaterThan(low, 1.7)
        XCTAssertLessThan(high, 1.1)
    }
    func testRNNoiseSuppressesStationarySyntheticNoise() {
        let channel = hop_audio_create(48000)!
        defer { hop_audio_destroy(channel) }
        hop_audio_configure(channel, 1, false, true, false)
        var seed: UInt32 = 42, before = 0.0, after = 0.0
        for block in 0..<150 {
            let input = (0..<480).map { _ -> Float in
                seed = seed &* 1664525 &+ 1013904223
                return (Float(seed >> 8) / Float(1 << 24) * 2 - 1) * 0.05
            }
            let output = render(channel, input)
            XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= 1 })
            if block > 50 {
                before += input.reduce(0) { $0 + Double($1 * $1) }
                after += output.reduce(0) { $0 + Double($1 * $1) }
            }
        }
        XCTAssertLessThan(after, before * 0.4)
    }
    func testChannelConfigurationRoundTripsAndClampsInvalidGain() throws {
        var settings = SoundChannelSettings()
        settings.gain = 4; settings.denoise = true; settings.bass = true
        XCTAssertEqual(settings.safeGain, 2)
        let command = SoundWorkerCommand(start: true, meters: false, inputs: [.init(uid: "test", settings: settings)])
        let read = try JSONDecoder().decode(SoundWorkerCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(read.inputs[0].settings, settings)
        settings.gain = .nan
        XCTAssertEqual(settings.safeGain, 1)
    }
    func testGlobalDenoiseAppliesToEveryInputWithoutChangingSavedChoices() throws {
        var original = SoundChannelSettings()
        let first = SoundInputConfiguration(uid: "first", settings: original, denoiseAll: true)
        original.denoise = true
        let second = SoundInputConfiguration(uid: "second", settings: original, denoiseAll: true)
        let command = SoundWorkerCommand(inputs: [first, second])
        let read = try JSONDecoder().decode(SoundWorkerCommand.self, from: JSONEncoder().encode(command))
        XCTAssertTrue(read.inputs.allSatisfy { $0.settings.denoise })
        original.denoise = false
        XCTAssertFalse(SoundInputConfiguration(uid: "first", settings: original).settings.denoise)
        original.denoise = true
        XCTAssertTrue(SoundInputConfiguration(uid: "second", settings: original).settings.denoise)
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
}
