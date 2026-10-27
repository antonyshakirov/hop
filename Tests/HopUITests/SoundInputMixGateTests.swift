import CoreAudio
import HopAudioDSP
import HopAudioEngine
import HopCore
import XCTest

final class SoundInputMixGateTests: XCTestCase {
    private func channel(_ value: Float) throws -> SoundAudioChannel {
        let channel = try SoundAudioChannel(rate: 48000)
        var samples = [Float](repeating: value, count: 128)
        samples.withUnsafeMutableBytes { bytes in
            var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
                mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            XCTAssertEqual(hop_audio_push(channel.pointer, &buffer, 64), 64)
        }
        return channel
    }
    private func render(_ gate: SoundInputMixGate) -> [Float] {
        var samples = [Float](repeating: -1, count: 32)
        samples.withUnsafeMutableBytes { bytes in
            var buffer = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
                mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
            gate.render(&buffer, frames: 16)
        }
        return samples
    }
    func testAccessoryMuteSilencesEveryMicrophoneButKeepsMusicAndConsumesMutedSamples() throws {
        let gate = SoundInputMixGate(), token = UUID()
        let first = try channel(0.1), second = try channel(0.2), music = try channel(0.05)
        music.configure(.init())
        gate.replace(microphones: [(first, .init()), (second, .init())], applications: [music], token: token)
        XCTAssertTrue(gate.setMuted(true, token: token))
        XCTAssertTrue(render(gate).allSatisfy { abs($0 - 0.05) < 0.0001 })
        XCTAssertEqual(hop_audio_queued(first.pointer), 48)
        XCTAssertEqual(hop_audio_queued(second.pointer), 48)
        XCTAssertTrue(gate.muted)
    }
    func testLiveRowUpdatesRetainAccessoryMuteAndRowMuteSurvivesAccessoryUnmute() throws {
        let gate = SoundInputMixGate(), token = UUID()
        let first = try channel(0.1), second = try channel(0.2)
        var row = SoundChannelSettings(); row.muted = true
        gate.replace(microphones: [(first, row), (second, .init())], applications: [], token: token)
        XCTAssertTrue(gate.setMuted(true, token: token))
        gate.replace(microphones: [(first, row), (second, .init())], applications: [], token: token)
        XCTAssertTrue(render(gate).allSatisfy { $0 == 0 })
        XCTAssertTrue(gate.setMuted(false, token: token))
        let audible = render(gate)
        XCTAssertTrue(audible.allSatisfy { $0 <= 0.2001 })
        XCTAssertGreaterThan(audible.last!, 0)
    }
    func testRetiredAccessoryTokenCannotChangeNewCaptureOrReviveStoppedInputs() throws {
        let gate = SoundInputMixGate(), old = UUID(), current = UUID()
        let mic = try channel(0.1)
        gate.replace(microphones: [(mic, .init())], applications: [], token: old)
        XCTAssertTrue(gate.setMuted(true, token: old))
        gate.replace(microphones: [(mic, .init())], applications: [], token: current)
        XCTAssertFalse(gate.muted)
        XCTAssertFalse(gate.setMuted(true, token: old))
        XCTAssertGreaterThan(render(gate).last!, 0)
        gate.replace(microphones: [], applications: [], token: nil)
        XCTAssertFalse(gate.setMuted(false, token: current))
        XCTAssertTrue(render(gate).allSatisfy { $0 == 0 })
    }
}
