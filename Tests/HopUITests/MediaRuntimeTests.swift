import AppKit
import AVFoundation
import CoreImage
import Vision
import HopCore
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Hop

final class MediaRuntimeTests: XCTestCase {
    func testCompressedImageIsJPEGButTransparencyStaysPNG() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try XCTUnwrap(MediaImageEngine.bitmap(.init(width: 256, height: 128)))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 128))
        let image = try XCTUnwrap(context.makeImage())
        let full = root.appendingPathComponent("full.png")
        let compressed = root.appendingPathComponent("compressed.jpg")
        XCTAssertEqual(MediaImageEngine.fileExtension(image, quality: .full), "png")
        XCTAssertEqual(MediaImageEngine.fileExtension(image, quality: .compressed(70)), "jpg")
        try MediaImageEngine.write(image, to: full, quality: .full)
        try MediaImageEngine.write(image, to: compressed, quality: .compressed(70))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(compressed as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(try MediaImageEngine.read(compressed).width, 256)
        context.clear(CGRect(x: 128, y: 0, width: 128, height: 128))
        let alpha = try XCTUnwrap(context.makeImage())
        XCTAssertEqual(MediaImageEngine.fileExtension(alpha, quality: .compressed(70)), "png")
        let transparent = root.appendingPathComponent("alpha.png")
        try MediaImageEngine.write(alpha, to: transparent, quality: .compressed(70))
        let bytes = try MediaImageEngine.pixels(MediaImageEngine.read(transparent))
        XCTAssertEqual(bytes[255 * 4 + 3], 0)
        XCTAssertEqual(bytes[3], 255)
    }
    @MainActor
    func testMixedQueueExportsSelectedThenAllAtBothQualityLevels() async throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: SettingsKey.mediaRemoveCompleted)
        defer {
            if let saved { defaults.set(saved, forKey: SettingsKey.mediaRemoveCompleted) }
            else { defaults.removeObject(forKey: SettingsKey.mediaRemoveCompleted) }
        }
        defaults.set(false, forKey: SettingsKey.mediaRemoveCompleted)
        guard ProcessInfo.processInfo.environment["HOP_MEDIA_INSTALL"] == "1",
              let imagePath = ProcessInfo.processInfo.environment["HOP_MEDIA_IMAGE"],
              let videoPath = ProcessInfo.processInfo.environment["HOP_MEDIA_VIDEO"] else {
            throw XCTSkip("Provide explicit model installation and mixed media fixtures")
        }
        if !MediaModelStore.ready { try await MediaModelStore.install() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = [URL(fileURLWithPath: imagePath), URL(fileURLWithPath: videoPath)]
        let originals = try sources.map { try Data(contentsOf: $0) }
        let controller = MediaController(operation: .upscale)
        controller.destination = root
        controller.add(sources)
        try await waitForController(controller, timeout: 90)
        XCTAssertEqual(controller.items.count, 2)
        XCTAssertEqual(controller.items.map(\.video), [false, true])
        XCTAssertEqual(controller.items.map(\.sourceBytes), originals.map { Int64($0.count) })
        XCTAssertTrue(controller.allFilesSelected)
        controller.toggleSelection(controller.items[1].id)
        controller.export(quality: .compressed(70), background: .transparent)
        try await waitForController(controller, timeout: 90)
        let jpeg = try XCTUnwrap(controller.items[0].exported)
        XCTAssertEqual(jpeg.pathExtension, "jpg")
        XCTAssertEqual(controller.items[0].outputBytes, Int64(try Data(contentsOf: jpeg).count))
        XCTAssertNil(controller.items[1].outputBytes)
        XCTAssertTrue(controller.selection.isEmpty)
        XCTAssertNil(controller.items[1].exported)
        XCTAssertEqual(try MediaImageEngine.read(jpeg).width, controller.items[0].size.width * 2)
        controller.selectAllFiles()
        controller.export(quality: .full, background: .transparent)
        try await waitForController(controller, timeout: 90)
        let png = try XCTUnwrap(controller.items[0].exported)
        let mov = try XCTUnwrap(controller.items[1].exported)
        XCTAssertEqual(png.pathExtension, "png")
        XCTAssertEqual(mov.pathExtension, "mov")
        XCTAssertEqual(controller.items[0].outputBytes, Int64(try Data(contentsOf: png).count))
        XCTAssertEqual(controller.items[1].outputBytes, Int64(try Data(contentsOf: mov).count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpeg.path), "Re-export must preserve an earlier output")
        let fullAsset = AVURLAsset(url: mov)
        let fullTrack = try await fullAsset.loadTracks(withMediaType: .video)[0]
        let formats = try await fullTrack.load(.formatDescriptions)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(formats[0]), kCMVideoCodecType_AppleProRes422HQ)
        controller.toggleSelection(controller.items[1].id)
        controller.export(quality: .compressed(70), background: .transparent)
        try await waitForController(controller, timeout: 90)
        let mp4 = try XCTUnwrap(controller.items[1].exported)
        XCTAssertEqual(mp4.pathExtension, "mp4")
        XCTAssertEqual(controller.items[1].outputBytes, Int64(try Data(contentsOf: mp4).count))
        XCTAssertEqual(controller.items[0].exported, png, "Exporting selected video must leave the photo alone")
        XCTAssertLessThan(try Data(contentsOf: mp4).count, try Data(contentsOf: mov).count)
        for output in [mov, mp4] {
            let asset = AVURLAsset(url: output)
            let info = try await MediaVideoEngine.info(output)
            XCTAssertEqual(info.size.width, controller.items[1].size.width * 2)
            XCTAssertEqual(info.duration, controller.items[1].duration, accuracy: 0.02)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            let originalAudio = try await AVURLAsset(url: sources[1]).loadTracks(withMediaType: .audio)
            XCTAssertEqual(audio.count, 2)
            for (track, before) in zip(audio, originalAudio) {
                let description = try await track.load(.formatDescriptions)[0]
                let originalDescription = try await before.load(.formatDescriptions)[0]
                let asbd = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description)).pointee
                let originalASBD = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(originalDescription)).pointee
                XCTAssertEqual(asbd.mChannelsPerFrame, originalASBD.mChannelsPerFrame)
                XCTAssertEqual(asbd.mSampleRate, originalASBD.mSampleRate)
                XCTAssertEqual(asbd.mFormatID, output == mov ? kAudioFormatLinearPCM : kAudioFormatMPEG4AAC)
                let range = try await track.load(.timeRange)
                let originalRange = try await before.load(.timeRange)
                XCTAssertEqual(range.start.seconds, originalRange.start.seconds, accuracy: 0.025)
                XCTAssertEqual(range.duration.seconds, originalRange.duration.seconds, accuracy: 0.05)
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 4)
        for (url, original) in zip(sources, originals) { XCTAssertEqual(try Data(contentsOf: url), original) }
    }

    @MainActor
    func testSuccessfulExportCleanupAndNewImportsDoNotRepeatCompletedFiles() async throws {
        guard let path = ProcessInfo.processInfo.environment["HOP_MEDIA_IMAGE"] else {
            throw XCTSkip("Provide a portrait fixture for real queue cleanup acceptance")
        }
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: SettingsKey.mediaRemoveCompleted)
        defer {
            if let saved { defaults.set(saved, forKey: SettingsKey.mediaRemoveCompleted) }
            else { defaults.removeObject(forKey: SettingsKey.mediaRemoveCompleted) }
        }
        defaults.removeObject(forKey: SettingsKey.mediaRemoveCompleted)
        XCTAssertTrue(MediaController.removesCompleted)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: source)
        let controller = MediaController(operation: .background)
        controller.destination = folder
        controller.add([source, folder.appendingPathComponent("missing.png")])
        try await waitForController(controller)
        XCTAssertTrue(controller.allFilesSelected)
        controller.export(quality: .full, background: .transparent)
        try await waitForController(controller)
        XCTAssertEqual(controller.items.count, 1, "Only a successfully exported row is removed")
        XCTAssertNotNil(controller.items[0].error)
        XCTAssertEqual(controller.scopedItems.count, 1, "Failed files stay selected for review")
        let first = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        XCTAssertEqual(first.count, 1)
        defaults.set(false, forKey: SettingsKey.mediaRemoveCompleted)
        controller.add([source])
        try await waitForController(controller)
        controller.export(quality: .full, background: .transparent)
        try await waitForController(controller)
        let kept = try XCTUnwrap(controller.items.first { $0.url == source })
        XCTAssertNotNil(kept.exported)
        XCTAssertFalse(controller.selection.contains(kept.id))
        let another = folder.appendingPathComponent("another.jpg")
        try original.write(to: another)
        controller.add([another])
        try await waitForController(controller)
        XCTAssertFalse(controller.scopedItems.contains { $0.id == kept.id }, "New imports must not select completed rows")
        XCTAssertTrue(controller.scopedItems.contains { $0.url == another })
        XCTAssertTrue(FileManager.default.fileExists(atPath: first[0].path))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testResizePreservesTransparencyAndDimensions() throws {
        let context = CGContext(data: nil, width: 16, height: 8, bitsPerComponent: 8,
                                bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        let resized = try MediaImageEngine.resize(image, to: MediaSize(width: 32, height: 16))
        XCTAssertEqual(resized.width, 32)
        XCTAssertEqual(resized.height, 16)
        let bytes = try MediaImageEngine.pixels(resized)
        XCTAssertEqual(bytes[3], 255)
        XCTAssertEqual(bytes[31 * 4 + 3], 0)
    }

    func testModelRejectsUntrustedDownload() {
        XCTAssertFalse(MediaModelStore.validArchive(Data("incorrect model".utf8)))
    }

    func testRealModelInferencePreservesAlpha() async throws {
        guard let path = ProcessInfo.processInfo.environment["HOP_MEDIA_MODEL"] else {
            throw XCTSkip("Provide HOP_MEDIA_MODEL for real inference acceptance")
        }
        let context = CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8,
                                bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0.25, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = try XCTUnwrap(context.makeImage())
        let upscaler = try MediaUpscaler(modelURL: URL(fileURLWithPath: path))
        let result = try upscaler.enhance(image, to: MediaSize(width: 64, height: 32)) { _ in }
        XCTAssertEqual(result.width, 64)
        XCTAssertEqual(result.height, 32)
        let bytes = try MediaImageEngine.pixels(result)
        XCTAssertEqual(bytes[3], 255)
        XCTAssertEqual(bytes[63 * 4 + 3], 0)
        let resized = try MediaImageEngine.resize(image, to: MediaSize(width: 64, height: 32))
        XCTAssertNotEqual(bytes, try MediaImageEngine.pixels(resized))
    }

    func testRealModelKeepsTopAndBottomInPlace() throws {
        guard let path = ProcessInfo.processInfo.environment["HOP_MEDIA_MODEL"] else { throw XCTSkip("Real model needed") }
        let context = MediaImageEngine.bitmap(MediaSize(width: 32, height: 400))!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 200))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 200, width: 32, height: 200))
        let image = try XCTUnwrap(context.makeImage())
        let result = try MediaUpscaler(modelURL: URL(fileURLWithPath: path)).enhance(image, to: MediaSize(width: 64, height: 800)) { _ in }
        let bytes = try MediaImageEngine.pixels(result)
        let baseline = try MediaImageEngine.pixels(MediaImageEngine.resize(image, to: MediaSize(width: 64, height: 800)))
        for row in [10, 195, 205, 385, 395, 405, 590, 780] {
            let at = (row * 64 + 10) * 4
            XCTAssertEqual(bytes[at] > bytes[at + 2], baseline[at] > baseline[at + 2], "wrong vertical tile at row \(row)")
        }
    }

    @MainActor
    func testControllerQueuePreviewAndReexport() async throws {
        guard ProcessInfo.processInfo.environment["HOP_MEDIA_INSTALL"] == "1",
              let imagePath = ProcessInfo.processInfo.environment["HOP_MEDIA_IMAGE"] else {
            throw XCTSkip("Explicit model installation acceptance needs HOP_MEDIA_INSTALL=1")
        }
        if !MediaModelStore.ready { try await MediaModelStore.install() }
        XCTAssertTrue(MediaModelStore.ready)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var controller = MediaController()
        controller.destination = root
        controller.add([URL(fileURLWithPath: "/missing-image.png"), URL(fileURLWithPath: imagePath)])
        try await waitForController(controller)
        XCTAssertEqual(controller.items.count, 2)
        XCTAssertNotNil(controller.items[0].error)
        controller.selected = controller.items[1].id
        controller.run(preview: true, background: .transparent)
        try await waitForController(controller)
        XCTAssertNotNil(controller.selectedItem?.result)
        XCTAssertFalse(controller.selectedItem?.subjects.isEmpty ?? true)
        controller.run(preview: false, background: .transparent)
        try await waitForController(controller)
        let firstExport = try XCTUnwrap(controller.selectedItem?.exported)
        controller.run(preview: true, background: .transparent)
        try await waitForController(controller)
        XCTAssertEqual(controller.selectedItem?.exported, firstExport)
        let backgroundController = controller
        controller = MediaController(operation: .upscale)
        controller.destination = root
        controller.add([URL(fileURLWithPath: imagePath)])
        try await waitForController(controller)
        XCTAssertEqual(backgroundController.selectedItem?.exported, firstExport)
        controller.run(preview: true, background: .transparent)
        try await waitForController(controller)
        XCTAssertNotNil(controller.selectedItem?.result)
        XCTAssertNil(controller.selectedItem?.error)
        controller.run(preview: false, background: .transparent)
        try await waitForController(controller)
        let enlarged = try XCTUnwrap(controller.selectedItem?.exported)
        let image = try MediaImageEngine.read(enlarged)
        XCTAssertEqual(image.width, controller.selectedItem!.size.width * 2)
        let original = try MediaImageEngine.read(URL(fileURLWithPath: imagePath))
        let comparison = MediaSize(width: 64, height: 43)
        let before = try MediaImageEngine.pixels(MediaImageEngine.resize(original, to: comparison))
        let after = try MediaImageEngine.pixels(MediaImageEngine.resize(image, to: comparison))
        let averageDifference = zip(before, after).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) } / Double(before.count)
        XCTAssertLessThan(averageDifference, 12, "Real photo regions must stay in place")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
        if let folder = ProcessInfo.processInfo.environment["HOP_MEDIA_OUTPUTS"] {
            try FileManager.default.copyItem(at: enlarged, to: URL(fileURLWithPath: folder).appendingPathComponent("upscaled-photo.png"))
        }
    }

    func testRealModelReachesEightKThroughMultiplePasses() throws {
        guard let path = ProcessInfo.processInfo.environment["HOP_MEDIA_MODEL"] else { throw XCTSkip("Real model needed") }
        let canvas = try XCTUnwrap(MediaImageEngine.bitmap(MediaSize(width: 32, height: 18)))
        canvas.setFillColor(CGColor(red: 0.4, green: 0.6, blue: 0.8, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
        let image = try XCTUnwrap(canvas.makeImage())
        let result = try MediaUpscaler(modelURL: URL(fileURLWithPath: path)).enhance(image,
            to: MediaSize(width: 7680, height: 4320)) { _ in }
        XCTAssertEqual(result.width, 7680)
        XCTAssertEqual(result.height, 4320)
    }

    func testRealBackgroundRemovalAndVideoAudio() async throws {
        guard let imagePath = ProcessInfo.processInfo.environment["HOP_MEDIA_IMAGE"],
              let videoPath = ProcessInfo.processInfo.environment["HOP_MEDIA_VIDEO"] else {
            throw XCTSkip("Provide portrait and video fixtures for Vision acceptance")
        }
        let image = try MediaImageEngine.read(URL(fileURLWithPath: imagePath))
        let (foreground, subjects) = try MediaImageEngine.foreground(image, subject: 0)
        XCTAssertFalse(subjects.isEmpty)
        let pixels = try MediaImageEngine.pixels(foreground)
        let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        XCTAssertGreaterThan(alpha.filter { $0 < 32 }.count, alpha.count / 10)
        XCTAssertGreaterThan(alpha.filter { $0 > 220 }.count, alpha.count / 10)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(fileURLWithPath: videoPath)
        let original = try Data(contentsOf: source)
        let output = try await MediaVideoEngine.export(source, to: root, operation: .background,
            output: nil, subject: 0, background: .transparent, upscaler: nil) { _ in }
        let asset = AVURLAsset(url: output)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let sourceAsset = AVURLAsset(url: source)
        let sourceAudio = try await sourceAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 2)
        for (track, before) in zip(audio, sourceAudio) {
            let formats = try await track.load(.formatDescriptions)
            let beforeFormats = try await before.load(.formatDescriptions)
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formats[0])!.pointee
            let beforeASBD = CMAudioFormatDescriptionGetStreamBasicDescription(beforeFormats[0])!.pointee
            XCTAssertEqual(asbd.mChannelsPerFrame, beforeASBD.mChannelsPerFrame)
            XCTAssertEqual(asbd.mSampleRate, beforeASBD.mSampleRate)
            let range = try await track.load(.timeRange)
            let beforeRange = try await before.load(.timeRange)
            XCTAssertEqual(range.start.seconds, beforeRange.start.seconds, accuracy: 0.025)
            XCTAssertEqual(range.duration.seconds, beforeRange.duration.seconds, accuracy: 0.05)
        }
        let duration = try await asset.load(.duration).seconds
        let originalDuration = try await sourceAsset.load(.duration).seconds
        XCTAssertEqual(duration, originalDuration, accuracy: 0.02)
        let frame = try await MediaVideoEngine.frame(output)
        let framePixels = try MediaImageEngine.pixels(frame)
        let frameAlpha = stride(from: 3, to: framePixels.count, by: 4).map { framePixels[$0] }
        XCTAssertGreaterThan(frameAlpha.filter { $0 < 32 }.count, frameAlpha.count / 10)
        XCTAssertGreaterThan(frameAlpha.filter { $0 > 220 }.count, frameAlpha.count / 10)
        XCTAssertEqual(original, try Data(contentsOf: source))
        if let folder = ProcessInfo.processInfo.environment["HOP_MEDIA_OUTPUTS"] {
            try MediaImageEngine.writePNG(foreground, to: URL(fileURLWithPath: folder).appendingPathComponent("background-removed.png"))
            try FileManager.default.copyItem(at: output, to: URL(fileURLWithPath: folder).appendingPathComponent("background-removed.mov"))
        }
    }

    func testVideoUpscalePreservesFrameTimesAndDuration() async throws {
        guard let path = ProcessInfo.processInfo.environment["HOP_MEDIA_MODEL"] else { throw XCTSkip("Real model needed") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("input.mov")
        let writer = try AVAssetWriter(outputURL: source, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 32, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 16])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        let times = [0, 30, 80, 110]
        for (n, time) in times.enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer), kCVReturnSuccess)
            let image = CIImage(color: CIColor(red: n.isMultiple(of: 2) ? 1 : 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 16))
            MediaImageEngine.context.render(image, to: buffer!)
            XCTAssertTrue(adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(time), timescale: 600)))
        }
        input.markAsFinished(); writer.endSession(atSourceTime: CMTime(value: 150, timescale: 600))
        await writer.finishWriting(); XCTAssertEqual(writer.status, .completed)
        let original = try Data(contentsOf: source)
        let output = try await MediaVideoEngine.export(source, to: root, operation: .upscale,
            output: MediaSize(width: 64, height: 32), subject: 0, background: .transparent,
            upscaler: MediaUpscaler(modelURL: URL(fileURLWithPath: path))) { _ in }
        let info = try await MediaVideoEngine.info(output)
        XCTAssertEqual(info.size, MediaSize(width: 64, height: 32))
        XCTAssertEqual(info.duration, 0.25, accuracy: 0.02)
        XCTAssertEqual(original, try Data(contentsOf: source))
        let asset = AVURLAsset(url: output)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: asset)
        let frames = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(frames); XCTAssertTrue(reader.startReading())
        var actual: [Double] = []
        while let sample = frames.copyNextSampleBuffer() { actual.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
        XCTAssertEqual(actual.count, times.count)
        for (a, b) in zip(actual, times) { XCTAssertEqual(a, Double(b) / 600, accuracy: 0.002) }
        let cancelled = Task {
            try await MediaVideoEngine.export(source, to: root, operation: .upscale,
                output: MediaSize(width: 64, height: 32), subject: 0, background: .transparent,
                upscaler: MediaUpscaler(modelURL: URL(fileURLWithPath: path))) { value in
                    if value > 0 { withUnsafeCurrentTask { $0?.cancel() } }
                }
        }
        do { _ = try await cancelled.value; XCTFail("Cancellation must throw") }
        catch is CancellationError { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".hop-media-") })
    }

    @MainActor
    func testControllerCancellationClearsPartialProgressAndOutput() async throws {
        guard ProcessInfo.processInfo.environment["HOP_MEDIA_INSTALL"] == "1",
              let path = ProcessInfo.processInfo.environment["HOP_MEDIA_IMAGE"] else {
            throw XCTSkip("Provide explicit model installation and portrait for controller cancellation")
        }
        if !MediaModelStore.ready { try await MediaModelStore.install() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = MediaController(operation: .upscale)
        controller.destination = root
        controller.add([URL(fileURLWithPath: path)])
        try await waitForController(controller)
        controller.items[0].resolution = .eightK
        controller.run(preview: false, background: .transparent)
        let deadline = Date().addingTimeInterval(20)
        while controller.items[0].progress == 0 && controller.busy {
            guard Date() < deadline else { controller.cancel(); throw MediaFailure.output }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(controller.busy, "Cancel while real inference is running")
        controller.cancel()
        try await waitForController(controller)
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(controller.items[0].progress, 0)
        XCTAssertNil(controller.items[0].exported)
        XCTAssertNil(controller.items[0].error)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @MainActor
    private func waitForController(_ controller: MediaController, timeout: TimeInterval = 30) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while controller.locked {
            guard Date() < deadline else { controller.cancel(); throw MediaFailure.output }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

}
