import AVFoundation
import CoreMedia
import OSLog

protocol SoundMicrophoneCaptureBackend: AnyObject {
    var uid: String { get }
    func start(sample: @escaping (CMSampleBuffer) -> Void, failed: @escaping (Error) -> Void) throws
    func stop()
}

enum SoundMicrophoneCaptureError: Error { case missingDevice, unsupported, noSamples, interrupted }

/// Starts the exact microphone and returns only after converted PCM is available; stop drains capture.
public final class SoundMicrophoneCapture {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "HopMix")
    private let backend: SoundMicrophoneCaptureBackend
    private let converter = SoundMicrophonePCMConverter()
    private let lock = NSLock()
    private let firstFrame = DispatchSemaphore(value: 0)
    private let consume: (AVAudioPCMBuffer) -> Void
    private let failed: (Error) -> Void
    private var buffer: AVAudioPCMBuffer?
    private var previousFormat: AVAudioFormat?
    private var ready = false
    private var stopped = false
    private var failure: Error?

    public convenience init(uid: String, consume: @escaping (AVAudioPCMBuffer) -> Void,
                            failed: @escaping (Error) -> Void) throws {
        try self.init(uid: uid, backend: SoundNativeMicrophoneCapture(uid: uid),
                      firstFrameTimeout: 1.5, consume: consume, failed: failed)
    }

    init(uid: String, backend: SoundMicrophoneCaptureBackend, firstFrameTimeout: TimeInterval,
         consume: @escaping (AVAudioPCMBuffer) -> Void, failed: @escaping (Error) -> Void) throws {
        guard backend.uid == uid else { throw SoundMicrophoneCaptureError.missingDevice }
        self.backend = backend; self.consume = consume; self.failed = failed
        do {
            try backend.start(sample: { [weak self] in self?.receive($0) }, failed: { [weak self] in self?.fail($0) })
            _ = firstFrame.wait(timeout: .now() + max(0, min(3, firstFrameTimeout)))
            lock.lock()
            let error = failure, accepted = ready && !stopped
            lock.unlock()
            if let error { throw error }
            guard accepted else { throw SoundMicrophoneCaptureError.noSamples }
        } catch { stop(); throw error }
    }

    private func receive(_ sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, failure == nil, CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample),
              let description = CMSampleBufferGetFormatDescription(sample) else { return }
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0, count <= 131072 else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard format.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
              format.sampleRate.isFinite, format.sampleRate >= 8000,
              (1...32).contains(format.channelCount) else { return }
        let changed = previousFormat?.isEqual(format) != true
        if changed {
            Self.log.notice("microphone-pcm-received rate=\(format.sampleRate, privacy: .public) channels=\(format.channelCount, privacy: .public)")
            previousFormat = format
        }
        if buffer?.format.isEqual(format) != true || Int(buffer?.frameCapacity ?? 0) < count {
            buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        }
        guard let buffer else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count),
                                                          into: buffer.mutableAudioBufferList) == noErr,
              let converted = converter.convert(buffer) else { return }
        consume(converted)
        if changed {
            Self.log.notice("microphone-pcm-converted rate=\(format.sampleRate, privacy: .public) channels=\(format.channelCount, privacy: .public)")
        }
        if !ready { ready = true; firstFrame.signal() }
    }

    private func fail(_ error: Error) {
        lock.lock()
        guard !stopped, failure == nil else { lock.unlock(); return }
        failure = error
        let wasReady = ready
        firstFrame.signal()
        lock.unlock()
        if wasReady { failed(error) }
    }

    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true; firstFrame.signal()
        lock.unlock()
        backend.stop()
    }

    deinit { stop() }
}
