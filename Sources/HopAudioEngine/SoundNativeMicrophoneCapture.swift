import AVFoundation
import CoreMedia

final class SoundNativeMicrophoneCapture: NSObject, SoundMicrophoneCaptureBackend,
                                          AVCaptureAudioDataOutputSampleBufferDelegate {
    let uid: String
    private let device: AVCaptureDevice
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let lifecycle = DispatchQueue(label: "Hop.Microphone.Lifecycle")
    private let callbacks = DispatchQueue(label: "Hop.Microphone.PCM")
    private var sample: ((CMSampleBuffer) -> Void)?
    private var failure: ((Error) -> Void)?
    private var observations: [NSObjectProtocol] = []

    init(uid: String) throws {
        guard let device = AVCaptureDevice(uniqueID: uid), device.uniqueID == uid,
              device.hasMediaType(.audio), device.isConnected else { throw SoundMicrophoneCaptureError.missingDevice }
        self.uid = uid; self.device = device
        super.init()
    }

    func start(sample: @escaping (CMSampleBuffer) -> Void, failed: @escaping (Error) -> Void) throws {
        callbacks.sync { self.sample = sample; failure = failed }
        try lifecycle.sync {
            try configure()
            let center = NotificationCenter.default
            for name in [AVCaptureSession.runtimeErrorNotification,
                         AVCaptureSession.wasInterruptedNotification,
                         AVCaptureSession.didStopRunningNotification] {
                observations.append(center.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                    let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error ?? SoundMicrophoneCaptureError.interrupted
                    self?.callbacks.async { [weak self] in self?.failure?(error) }
                })
            }
            output.setSampleBufferDelegate(self, queue: callbacks)
            session.startRunning()
            guard session.isRunning else { throw SoundMicrophoneCaptureError.interrupted }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw SoundMicrophoneCaptureError.unsupported }
        session.addInput(input)
        output.audioSettings = nil
        session.addOutput(output)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        sample?(sampleBuffer)
    }

    func stop() {
        lifecycle.sync {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            output.setSampleBufferDelegate(nil, queue: nil)
            session.stopRunning()
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
        }
        callbacks.sync { sample = nil; failure = nil }
    }
}
