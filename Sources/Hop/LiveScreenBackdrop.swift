import AppKit
import CoreImage
import ScreenCaptureKit

/// The screen under the drawing layer, streamed for the loupe and the blur.
/// SPEC: docs/spec.md — "Draw over the screen", the loupe and the blur.
@MainActor
final class LiveScreenBackdrop: NSObject, ObservableObject, SCStreamOutput {
    /// The newest frame, in the display's own pixels.
    @Published private(set) var frame: CGImage?

    private static let fps = 15

    private var stream: SCStream?
    private var starting = false
    private let queue = DispatchQueue(label: "hop.live-backdrop", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    var isRunning: Bool { stream != nil }

    func start(on screen: NSScreen?) {
        guard stream == nil, !starting, let screen else { return }
        starting = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.starting = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                let id = CaptureController.displayID(of: screen)
                guard let display = content.displays.first(where: { $0.displayID == id })
                        ?? content.displays.first else { return }
                let ours = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                let configuration = SCStreamConfiguration()
                configuration.width = Int(Double(display.width) * screen.backingScaleFactor)
                configuration.height = Int(Double(display.height) * screen.backingScaleFactor)
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
                configuration.showsCursor = false
                configuration.queueDepth = 3

                let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: ours),
                                      configuration: configuration, delegate: nil)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                try await stream.startCapture()
                self.stream = stream
            } catch {
                self.stream = nil
            }
        }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        frame = nil
        Task { try? await stream.stopCapture() }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let picture = CIImage(cvPixelBuffer: buffer)
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.frame = self.context.createCGImage(picture, from: picture.extent)
        }
    }
}
