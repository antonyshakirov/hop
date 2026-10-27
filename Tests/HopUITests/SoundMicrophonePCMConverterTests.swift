import AVFoundation
import HopAudioEngine
import XCTest
@testable import Hop

final class SoundMicrophonePCMConverterTests: XCTestCase {
    // Generated PCM stays in memory and is never played or written to a file.
    func testBluetoothRateAndChannelChangesKeepDurationPitchAndStereoOutput() throws {
        let converter = SoundMicrophonePCMConverter()
        for (rate, channels): (Double, AVAudioChannelCount) in [(48000, 1), (24000, 1), (48000, 1), (44100, 2), (16000, 1)] {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels))
            let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
            input.frameLength = 512
            var samples: [Float] = []
            for chunk in 0..<32 {
                fill(input, offset: chunk * 512)
                guard let output = converter.convert(input) else {
                    XCTFail("Valid microphone PCM was dropped after format changed to \(rate) / \(channels)")
                    break
                }
                XCTAssertEqual(output.format.sampleRate, 48000)
                XCTAssertEqual(output.format.channelCount, 2)
                let pointers = try XCTUnwrap(output.floatChannelData)
                for index in 0..<Int(output.frameLength) {
                    XCTAssertEqual(pointers[0][index], pointers[1][index], accuracy: 0.0001)
                    samples.append(pointers[0][index])
                }
            }
            let expectedFrames = Double(32 * 512) * 48000 / rate
            XCTAssertEqual(Double(samples.count), expectedFrames, accuracy: 512, "Duration at \(rate)")
            guard samples.count > 960 else { continue }
            let tail = Array(samples.dropFirst(960))
            let crossings = zip(tail, tail.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
            let frequency = Double(crossings) * 48000 / Double(tail.count - 1)
            XCTAssertEqual(frequency, 1000, accuracy: 12, "Pitch at \(rate)")
            XCTAssertGreaterThan(tail.map { abs($0) }.max() ?? 0, 0.05)
            XCTAssertLessThan(tail.map { abs($0) }.max() ?? 0, 0.35)
        }
    }

    func testLargerTapBuffersDoNotTruncateResampledInput() throws {
        let converter = SoundMicrophonePCMConverter()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
        var frames = 0
        var offset = 0
        for size: AVAudioFrameCount in [128, 512, 8192, 1024] {
            let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: size))
            input.frameLength = size
            fill(input, offset: offset); offset += Int(size)
            let output = try XCTUnwrap(converter.convert(input))
            frames += Int(output.frameLength)
        }
        XCTAssertEqual(Double(frames), Double(offset * 2), accuracy: 128,
                       "A larger Bluetooth callback must not lose half its samples")
    }

    func testMicrophoneCheckKeepsCorrectDurationAcrossBluetoothFormats() throws {
        let converter = SoundMicrophonePCMConverter()
        let recording = try SoundSampleBuffer(format: converter.outputFormat)
        var expectedDuration = 0.0
        for rate: Double in [48000, 24000, 48000] {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
            let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
            input.frameLength = 512
            for chunk in 0..<32 {
                fill(input, offset: chunk * 512)
                recording.append(try XCTUnwrap(converter.convert(input)))
            }
            expectedDuration += Double(32 * 512) / rate
        }
        XCTAssertEqual(recording.readings.duration, expectedDuration, accuracy: 0.02)
        let saved = try XCTUnwrap(recording.recorded())
        XCTAssertEqual(saved.format.sampleRate, 48000)
        XCTAssertEqual(saved.format.channelCount, 2)
    }

    private func fill(_ input: AVAudioPCMBuffer, offset: Int) {
        guard let pointers = input.floatChannelData else { XCTFail("Fixture requires Float32 PCM"); return }
        for channel in 0..<Int(input.format.channelCount) {
            for frame in 0..<Int(input.frameLength) {
                pointers[channel][frame] = Float(sin(Double(frame + offset) * 2 * .pi * 1000 / input.format.sampleRate) * 0.2)
            }
        }
    }
}
