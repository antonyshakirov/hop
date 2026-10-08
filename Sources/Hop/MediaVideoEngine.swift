import AVFoundation
import CoreImage
import HopCore
import Vision

enum MediaVideoEngine {
    struct Info {
        let size: MediaSize
        let duration: Double
        let framesPerSecond: Double
    }

    static func info(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaFailure.input }
        let native = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let rect = CGRect(origin: .zero, size: native).applying(transform)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, rect.width > 0, rect.height > 0,
              rect.width <= 16384, rect.height <= 16384 else { throw MediaFailure.tooLarge }
        let fps = Double(try await track.load(.nominalFrameRate))
        return Info(size: MediaSize(width: Int(rect.width.rounded()), height: Int(rect.height.rounded())), duration: duration, framesPerSecond: fps.isFinite && fps > 0 ? fps : 30)
    }

    static func frame(_ url: URL, at seconds: Double = 0) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func person(_ image: CGImage, request: VNGeneratePersonSegmentationRequest,
                       handler: VNSequenceRequestHandler) throws -> CGImage {
        try handler.perform([request], on: image)
        guard let mask = request.results?.first?.pixelBuffer else { throw MediaFailure.noSubject }
        return try MediaImageEngine.applyMask(CIImage(cvPixelBuffer: mask), to: CIImage(cgImage: image))
    }

    static func export(_ url: URL, to folder: URL, operation: MediaOperation, output: MediaSize?,
                       subject: Int, background: MediaBackground, upscaler: MediaUpscaler?,
                       progress: @escaping (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw MediaFailure.input }
        let metadata = try await info(url)
        let desired = output ?? metadata.size
        let size = MediaSize(width: desired.width / 2 * 2, height: desired.height / 2 * 2)
        guard size.width > 0, size.height > 0, size.rgbaBytes != nil,
              size.width <= 7680, size.height <= 7680 else { throw MediaFailure.tooLarge }
        let transparent: Bool
        if operation == .background, case .transparent = background { transparent = true } else { transparent = false }
        let ext = transparent ? "mov" : "mp4"
        let stage = folder.appendingPathComponent(".hop-media-\(UUID().uuidString).\(ext)")
        defer { try? FileManager.default.removeItem(at: stage) }
        let reader = try AVAssetReader(asset: asset)
        let videoReader = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        videoReader.alwaysCopiesSampleData = false
        guard reader.canAdd(videoReader) else { throw MediaFailure.input }
        reader.add(videoReader)
        let writer = try AVAssetWriter(outputURL: stage, fileType: transparent ? .mov : .mp4)
        let codec: AVVideoCodecType = transparent ? .hevcWithAlpha : (max(size.width, size.height) > 4096 ? .hevc : .h264)
        let videoWriter = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                       AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriter, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(videoWriter) else { throw MediaFailure.codec }
        writer.add(videoWriter)
        var audioReaders: [AVAssetReaderTrackOutput] = []
        var audioWriters: [AVAssetWriterInput] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let formats = try await track.load(.formatDescriptions)
            guard let format = formats.first, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
            else { throw MediaFailure.input }
            let audioReader = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            let audioWriter = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: asbd.mSampleRate,
                AVNumberOfChannelsKey: Int(asbd.mChannelsPerFrame), AVEncoderBitRateKey: 192_000
            ])
            guard reader.canAdd(audioReader), writer.canAdd(audioWriter) else { throw MediaFailure.codec }
            reader.add(audioReader); writer.add(audioWriter)
            audioReaders.append(audioReader); audioWriters.append(audioWriter)
        }
        let transform = try await videoTrack.load(.preferredTransform)
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNSequenceRequestHandler()
        guard writer.startWriting() else { throw writer.error ?? MediaFailure.codec }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else { writer.cancelWriting(); throw reader.error ?? MediaFailure.input }
        do {
            var nextVideo = videoReader.copyNextSampleBuffer()
            var nextAudio = audioReaders.map { $0.copyNextSampleBuffer() }
            while nextVideo != nil || nextAudio.contains(where: { $0 != nil }) {
                try Task.checkCancellation()
                let audioIndex = nextAudio.indices.filter { nextAudio[$0] != nil }.min {
                    CMSampleBufferGetPresentationTimeStamp(nextAudio[$0]!) < CMSampleBufferGetPresentationTimeStamp(nextAudio[$1]!)
                }
                if let i = audioIndex, let sample = nextAudio[i],
                   nextVideo == nil || CMSampleBufferGetPresentationTimeStamp(sample) <= CMSampleBufferGetPresentationTimeStamp(nextVideo!) {
                    try await waitReady(audioWriters[i], writer: writer)
                    guard audioWriters[i].append(sample) else { throw writer.error ?? MediaFailure.output }
                    nextAudio[i] = audioReaders[i].copyNextSampleBuffer()
                    continue
                }
                guard let sample = nextVideo, let buffer = CMSampleBufferGetImageBuffer(sample) else { throw MediaFailure.input }
                let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
                try await waitReady(videoWriter, writer: writer)
                guard let pool = adaptor.pixelBufferPool else { throw MediaFailure.output }
                try autoreleasepool {
                    let transformed = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
                    let oriented = transformed.transformed(by: CGAffineTransform(translationX: -transformed.extent.minX,
                                                                                 y: -transformed.extent.minY))
                    guard let image = MediaImageEngine.context.createCGImage(oriented, from: oriented.extent,
                        format: .RGBA8, colorSpace: MediaImageEngine.colorSpace) else { throw MediaFailure.input }
                    let processed: CGImage
                    if operation == .background {
                        let masked = try person(image, request: request, handler: handler)
                        processed = try MediaImageEngine.replaceBackground(masked, with: background)
                    } else {
                        guard let upscaler, let output else { throw MediaFailure.model }
                        processed = try upscaler.enhance(image, to: output) { tileProgress in
                            let duration = CMSampleBufferGetDuration(sample).seconds
                            let seconds = timestamp.seconds + (duration.isFinite && duration > 0 ? duration * tileProgress : 0)
                            progress(min(0.99, seconds / metadata.duration))
                        }
                    }
                    var pixel: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else { throw MediaFailure.output }
                    let resized = CIImage(cgImage: processed).transformed(by: CGAffineTransform(
                        scaleX: Double(size.width) / Double(processed.width), y: Double(size.height) / Double(processed.height)))
                    MediaImageEngine.context.render(resized, to: pixel, bounds: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                                                   colorSpace: MediaImageEngine.colorSpace)
                    guard adaptor.append(pixel, withPresentationTime: timestamp) else { throw writer.error ?? MediaFailure.output }
                }
                progress(min(0.99, timestamp.seconds / metadata.duration))
                nextVideo = videoReader.copyNextSampleBuffer()
            }
            guard reader.status == .completed else { throw reader.error ?? MediaFailure.input }
            try Task.checkCancellation()
            videoWriter.markAsFinished()
            audioWriters.forEach { $0.markAsFinished() }
            writer.endSession(atSourceTime: try await asset.load(.duration))
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw writer.error ?? MediaFailure.output }
            let result = folder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-\(operation.rawValue)-\(UUID().uuidString.prefix(8)).\(ext)")
            try FileManager.default.moveItem(at: stage, to: result)
            progress(1)
            return result
        } catch {
            reader.cancelReading()
            if writer.status == .writing { writer.cancelWriting() }
            throw error
        }
    }

    private static func waitReady(_ input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing, Date() < deadline else { throw writer.error ?? MediaFailure.output }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
