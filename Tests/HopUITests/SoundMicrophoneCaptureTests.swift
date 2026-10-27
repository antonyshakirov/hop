import AVFoundation
import CoreMedia
import XCTest
@testable import HopAudioEngine

final class SoundMicrophoneCaptureTests: XCTestCase {
    private final class Backend: SoundMicrophoneCaptureBackend {
        var uid = "fixture-mic"
        var frames: [CMSampleBuffer] = []
        var startError: Error?
        var starts = 0, stops = 0
        var sample: ((CMSampleBuffer) -> Void)?
        var failure: ((Error) -> Void)?
        func start(sample: @escaping (CMSampleBuffer) -> Void, failed: @escaping (Error) -> Void) throws {
            starts += 1; self.sample = sample; failure = failed
            if let startError { failed(startError); return }
            frames.forEach(sample)
        }
        func stop() { stops += 1 }
    }

    func testBluetoothNativeRateChangesConvertWithoutRestartingCapture() throws {
        let backend = Backend()
        backend.frames = [try pcm(48000), try pcm(24000), try pcm(48000)]
        var rates: [Double] = [], frames = 0
        let capture = try SoundMicrophoneCapture(uid: backend.uid, backend: backend, firstFrameTimeout: 0,
            consume: { buffer in
                rates.append(buffer.format.sampleRate)
                XCTAssertEqual(buffer.format.channelCount, 2)
                XCTAssertGreaterThan(abs(buffer.floatChannelData![0][Int(buffer.frameLength) - 1]), 0.01)
                frames += Int(buffer.frameLength)
            }, failed: { _ in XCTFail("Valid format changes cannot fail capture") })
        XCTAssertEqual(rates, [48000, 48000, 48000])
        XCTAssertGreaterThan(frames, 1500)
        XCTAssertEqual(backend.starts, 1)
        capture.stop()
        XCTAssertEqual(backend.stops, 1)
    }

    func testRunningSessionWithoutConvertedPCMIsNotReadyAndStops() {
        let backend = Backend()
        XCTAssertThrowsError(try SoundMicrophoneCapture(uid: backend.uid, backend: backend,
            firstFrameTimeout: 0, consume: { _ in XCTFail("No samples expected") }, failed: { _ in }))
        XCTAssertEqual(backend.starts, 1)
        XCTAssertEqual(backend.stops, 1)
    }

    func testInvalidPCMDoesNotAcknowledgeCapture() throws {
        let backend = Backend()
        let invalid = try pcm(48000)
        XCTAssertEqual(CMSampleBufferInvalidate(invalid), noErr)
        backend.frames = [invalid]
        XCTAssertThrowsError(try SoundMicrophoneCapture(uid: backend.uid, backend: backend,
            firstFrameTimeout: 0, consume: { _ in XCTFail("Invalid samples cannot become ready") }, failed: { _ in }))
        XCTAssertEqual(backend.stops, 1)
    }

    func testStopRejectsLateFramesAndFailureAndIsIdempotent() throws {
        let backend = Backend()
        let frame = try pcm(24000); backend.frames = [frame]
        var delivered = 0, failures = 0
        let capture = try SoundMicrophoneCapture(uid: backend.uid, backend: backend,
            firstFrameTimeout: 0, consume: { _ in delivered += 1 }, failed: { _ in failures += 1 })
        capture.stop(); capture.stop()
        backend.sample?(frame)
        backend.failure?(NSError(domain: "fixture", code: 1))
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(backend.stops, 1)
    }

    func testRuntimeFailureBeforeFirstPCMDoesNotReportSuccess() {
        let backend = Backend(); backend.startError = NSError(domain: "fixture", code: 99)
        XCTAssertThrowsError(try SoundMicrophoneCapture(uid: backend.uid, backend: backend,
            firstFrameTimeout: 0, consume: { _ in XCTFail("No samples expected") }, failed: { _ in })) {
            XCTAssertEqual(($0 as NSError).code, 99)
        }
        XCTAssertEqual(backend.stops, 1)
    }

    func testRuntimeFailureAfterReadinessRejectsLaterPCMAndReportsOnce() throws {
        let backend = Backend(), frame = try pcm(48000)
        backend.frames = [frame]
        var delivered = 0, failures = 0
        let capture = try SoundMicrophoneCapture(uid: backend.uid, backend: backend,
            firstFrameTimeout: 0, consume: { _ in delivered += 1 }, failed: { _ in failures += 1 })
        backend.failure?(NSError(domain: "fixture", code: 99))
        backend.failure?(NSError(domain: "fixture", code: 100))
        backend.sample?(frame)
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(delivered, 1)
        capture.stop()
        XCTAssertEqual(backend.stops, 1)
    }

    func testExactUIDIsRequiredWithoutDefaultMicrophoneFallback() {
        let backend = Backend()
        XCTAssertThrowsError(try SoundMicrophoneCapture(uid: "missing-selected-mic", backend: backend,
            firstFrameTimeout: 0, consume: { _ in XCTFail("Wrong device cannot deliver samples") }, failed: { _ in }))
        XCTAssertEqual(backend.starts, 0)
    }

    private func pcm(_ rate: Double, frames: AVAudioFrameCount = 512) throws -> CMSampleBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, frames)))
        pcm.frameLength = frames
        for index in 0..<Int(frames) { pcm.floatChannelData![0][index] = 0.2 }
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: nil, asbd: format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description), noErr)
        var block: CMBlockBuffer?
        let bytes = Int(pcm.audioBufferList.pointee.mBuffers.mDataByteSize)
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil,
            blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes, flags: 0, blockBufferOut: &block), noErr)
        let data = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferReplaceDataBytes(with: pcm.audioBufferList.pointee.mBuffers.mData!,
            blockBuffer: data, offsetIntoDestination: 0, dataLength: bytes), noErr)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateWithPacketDescriptions(allocator: nil, dataBuffer: data,
            dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: try XCTUnwrap(description), sampleCount: Int(frames),
            presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}
