import AVFoundation
import XCTest
@testable import Hop

final class SoundSampleBufferTests: XCTestCase {
    func testRecordingKeepsChannelsAndCapsLength() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                 sampleRate: 8000, channels: 2, interleaved: false))
        let chunk = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
        chunk.frameLength = 8000
        let channels = try XCTUnwrap(chunk.floatChannelData)
        for i in 0..<8000 { channels[0][i] = 0.25; channels[1][i] = -0.5 }
        let sample = try SoundSampleBuffer(format: format)
        for _ in 0..<12 { sample.append(chunk) }
        XCTAssertEqual(sample.readings.duration, 10)
        XCTAssertGreaterThan(sample.readings.level, 0.7)
        let recording = try XCTUnwrap(sample.recorded())
        XCTAssertEqual(recording.frameLength, 80000)
        XCTAssertEqual(recording.floatChannelData?[0][79999], 0.25)
        XCTAssertEqual(recording.floatChannelData?[1][79999], -0.5)
    }

    func testEmptySampleDoesNotProducePlaybackAndNonFiniteSamplesAreSilent() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let sample = try SoundSampleBuffer(format: format)
        XCTAssertNil(sample.recorded())
        let chunk = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        chunk.frameLength = 1; chunk.floatChannelData?[0][0] = .nan
        sample.append(chunk)
        XCTAssertEqual(sample.readings.level, 0)
        XCTAssertEqual(sample.recorded()?.floatChannelData?[0][0], 0)
    }
}
