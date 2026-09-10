import AppKit
import CoreImage
import OSLog
import ScreenCaptureKit

/// The screens under the drawing layer, streamed for the loupe and the blur.
/// SPEC: docs/spec.md — "Draw over the screen", the loupe and the blur.
@MainActor
final class LiveScreenBackdrop: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var frames: [UInt32: CGImage] = [:]

    private static let fps = 15
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "LiveBackdrop")

    private struct Cut: Hashable {
        let display: UInt32
        let side: Int
    }

    private var streams: [UInt32: SCStream] = [:]
    private var opening: Set<UInt32> = []
    /// SPEC: docs/spec.md — a stream that fails to start is not retried.
    private var refused: Set<UInt32> = []
    private var wanted: Set<UInt32> = []
    private var tiles: [Cut: CGImage] = [:]
    private let queue = DispatchQueue(label: "hop.live-backdrop", qos: .userInitiated)
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    func start(on screens: [NSScreen]) {
        var scales: [UInt32: CGFloat] = [:]
        for screen in screens {
            let id = CaptureController.displayID(of: screen)
            guard id != 0 else { continue }
            scales[id] = screen.backingScaleFactor
        }
        wanted = Set(scales.keys)
        for id in streams.keys where !wanted.contains(id) { drop(id) }
        for (id, scale) in scales where streams[id] == nil {
            guard !opening.contains(id), !refused.contains(id) else { continue }
            opening.insert(id)
            Task { [weak self] in await self?.open(id, scale) }
        }
    }

    private func open(_ id: UInt32, _ scale: CGFloat) async {
        defer { opening.remove(id) }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard wanted.contains(id) else { return }
            guard let display = content.displays.first(where: { $0.displayID == id }) else {
                Self.log.error("no display \(id) to stream")
                refused.insert(id)
                return
            }
            let ours = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let configuration = SCStreamConfiguration()
            configuration.width = Int(Double(display.width) * scale)
            configuration.height = Int(Double(display.height) * scale)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
            configuration.showsCursor = false
            configuration.queueDepth = 3

            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: ours),
                                  configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            guard wanted.contains(id) else { return await Self.close(stream) }
            streams[id] = stream
        } catch {
            Self.log.error("the screen stream did not start: \(error.localizedDescription)")
            refused.insert(id)
        }
    }

    func tiled(display: UInt32, side: Int) -> CGImage? {
        guard let frame = frames[display] else { return nil }
        let cut = Cut(display: display, side: side)
        if let ready = tiles[cut] { return ready }
        guard let picture = MarkupRender.tiled(CIImage(cgImage: frame), side: Double(side))
        else { return nil }
        tiles[cut] = picture
        return picture
    }

    private func drop(_ id: UInt32) {
        frames[id] = nil
        tiles = tiles.filter { $0.key.display != id }
        guard let running = streams.removeValue(forKey: id) else { return }
        Task { await Self.close(running) }
    }

    func stop() {
        wanted = []
        refused = []
        for id in streams.keys { drop(id) }
        frames = [:]
        tiles = [:]
    }

    /// SPEC: docs/spec.md — a stream that will not stop says so.
    private static func close(_ running: SCStream) async {
        do {
            try await running.stopCapture()
        } catch {
            log.error("the screen stream did not stop: \(error.localizedDescription)")
        }
    }

    private func display(of stream: SCStream) -> UInt32? {
        streams.first { $0.value === stream }?.key
    }

    /// SPEC: docs/spec.md — a stream that dies says so, and is asked for again.
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, let id = self.display(of: stream) else { return }
            Self.log.error("the screen stream stopped: \(error.localizedDescription)")
            self.drop(id)
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer,
                            of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        // The buffer is one of three in rotation: copy, never hold.
        let picture = CIImage(cvPixelBuffer: buffer)
        Task { @MainActor [weak self] in
            guard let self, let id = self.display(of: stream) else { return }
            self.tiles = self.tiles.filter { $0.key.display != id }
            guard let made = self.context.createCGImage(picture, from: picture.extent) else {
                Self.log.error("a streamed frame could not be read")
                return self.frames[id] = nil
            }
            self.frames[id] = made
        }
    }
}
