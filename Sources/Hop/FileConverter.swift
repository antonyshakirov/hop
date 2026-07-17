import AppKit
import AVFoundation
import HopCore
import PDFKit
import UniformTypeIdentifiers

/// Converter: a batch of PDFs/images/videos/audio → compressed copies.
/// Fully native (ImageIO + PDFKit + AVFoundation), no external dependencies.
@MainActor
final class FileConverter: ObservableObject {
    nonisolated static let formatKey = "convFormat"           // jpeg | png | heic | avif
    nonisolated static let scaleKey = "convScale"             // 0.25 | 0.5 | 0.75 | 1.0
    nonisolated static let qualityKey = "convQuality"         // 10...100 (images)
    nonisolated static let pdfQualityKey = "convPdfQuality"   // 10...100 — its own slider,
    // otherwise moving the PDF quality changed images too
    nonisolated static let destKey = "convDest"               // downloads | same | custom
    nonisolated static let destPathKey = "convDestPath"
    nonisolated static let videoFormatKey = "convVideoFormat" // mp4 | mov
    /// Legacy single "quality" (original | hevc | 1080 | 720 | 540) —
    /// migrated into resolution + compress on init, read-only since.
    nonisolated static let videoQualityKey = "convVideoQuality"
    nonisolated static let videoResolutionKey = "convVideoResolution" // original | 2160 | 1080 | 720 | 540
    nonisolated static let videoCompressKey = "convVideoCompress" // HEVC instead of H.264
    nonisolated static let autoClearKey = "convAutoClear"       // finished ones disappear on their own

    enum MediaKind: Sendable {
        case image, pdf, video, audio, unsupported
    }

    struct BatchFile: Identifiable {
        let url: URL
        var bytes: Int64 = 0
        var done = false
        /// The system failed to read/convert the file (for example, AVI
        /// classifies as video, but AVFoundation cannot read it).
        var failed = false
        var id: String { url.path }
    }

    struct Batch {
        var images: [BatchFile] = []
        var pdfs: [BatchFile] = []
        var videos: [BatchFile] = []
        var audios: [BatchFile] = []
        var unsupported: [BatchFile] = []

        var all: [BatchFile] { images + pdfs + videos + audios + unsupported }
        var isEmpty: Bool { all.isEmpty }

        func files(_ kind: MediaKind) -> [BatchFile] {
            switch kind {
            case .image: return images
            case .pdf: return pdfs
            case .video: return videos
            case .audio: return audios
            case .unsupported: return unsupported
            }
        }

        /// Files still waiting to be converted.
        func pending(_ kind: MediaKind) -> [URL] {
            files(kind).filter { !$0.done }.map(\.url)
        }

        mutating func append(_ url: URL, kind: MediaKind) {
            let size = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let file = BatchFile(url: url, bytes: size)
            switch kind {
            case .image: images.append(file)
            case .pdf: pdfs.append(file)
            case .video: videos.append(file)
            case .audio: audios.append(file)
            case .unsupported: unsupported.append(file)
            }
        }

        /// Remove listed files from the group (auto-clearing of finished ones).
        mutating func remove(_ doneSet: Set<URL>, kind: MediaKind) {
            func strip(_ list: inout [BatchFile]) {
                list.removeAll { doneSet.contains($0.url) }
            }
            switch kind {
            case .image: strip(&images)
            case .pdf: strip(&pdfs)
            case .video: strip(&videos)
            case .audio: strip(&audios)
            case .unsupported: strip(&unsupported)
            }
        }

        /// Drop everything finished from every group.
        mutating func clearDone() {
            images.removeAll(where: \.done)
            pdfs.removeAll(where: \.done)
            videos.removeAll(where: \.done)
            audios.removeAll(where: \.done)
        }

        /// Converted files stay in the list with a checkmark — it's clear
        /// what's already done versus what was added later.
        mutating func markDone(_ doneSet: Set<URL>, kind: MediaKind) {
            func mark(_ list: inout [BatchFile]) {
                for index in list.indices where doneSet.contains(list[index].url) {
                    list[index].done = true
                }
            }
            switch kind {
            case .image: mark(&images)
            case .pdf: mark(&pdfs)
            case .video: mark(&videos)
            case .audio: mark(&audios)
            case .unsupported: mark(&unsupported)
            }
        }

        mutating func markFailed(_ failedSet: Set<URL>, kind: MediaKind) {
            guard !failedSet.isEmpty else { return }
            func mark(_ list: inout [BatchFile]) {
                for index in list.indices where failedSet.contains(list[index].url) {
                    list[index].failed = true
                }
            }
            switch kind {
            case .image: mark(&images)
            case .pdf: mark(&pdfs)
            case .video: mark(&videos)
            case .audio: mark(&audios)
            case .unsupported: break
            }
        }
    }

    @Published var batch = Batch()
    @Published private(set) var busy = false
    @Published private(set) var activeKind: MediaKind?
    @Published private(set) var progress: String?
    /// Whole-batch progress 0...1: whole files done + the current video's fraction.
    @Published private(set) var batchFraction: Double?
    /// Fraction of the current file (0…1): for video/audio the encoder itself reports it.
    @Published private(set) var fileFraction: Double?
    /// Video file resolutions ("1080p") — read when files are added to the batch.
    @Published private(set) var videoResolutions: [String: String] = [:]
    @Published private(set) var lastResult: String?
    /// "current size → projected size": trial conversion of the group's first file.
    @Published private(set) var estimates: [MediaKind: String] = [:]
    /// Same per file (keyed by path): files vary in size,
    /// so the group total alone says nothing.
    @Published private(set) var fileEstimates: [String: String] = [:]
    private var estimateTokens: [MediaKind: UUID] = [:]

    /// Sample measurements at reference quality points: the slider
    /// interpolates instantly, without a trial conversion on every move.
    /// The struct and its math live in HopCore (unit-tested).
    private var curves: [MediaKind: EstimateCurve] = [:]
    // 55 is the default slider value: with it as a reference point the
    // estimate at defaults is a real measurement, not an interpolation
    nonisolated private static let curveQualities = [10, 35, 55, 80, 100]

    init() {
        Self.migrateLegacyVideoQuality()
    }

    /// AVIF is the main modern web format; the codec ships with recent macOS.
    static var avifSupported: Bool {
        let ids = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return ids.contains("public.avif")
    }

    nonisolated static var format: String {
        UserDefaults.standard.string(forKey: formatKey) ?? "jpeg"
    }

    nonisolated static var scale: Double {
        (UserDefaults.standard.object(forKey: scaleKey) as? Double) ?? 1.0
    }

    nonisolated static var quality: Double {
        // default 55 — aggressive, in the spirit of PDF compressors; tune further with the slider
        Double((UserDefaults.standard.object(forKey: qualityKey) as? Int) ?? 55) / 100
    }

    nonisolated static var pdfQuality: Double {
        Double((UserDefaults.standard.object(forKey: pdfQualityKey) as? Int) ?? 55) / 100
    }

    /// Quality per file kind: PDF has its own slider, images have theirs.
    nonisolated static func quality(for kind: MediaKind) -> Double {
        kind == .pdf ? pdfQuality : quality
    }

    nonisolated static var videoFormat: String {
        UserDefaults.standard.string(forKey: videoFormatKey) ?? "mp4"
    }

    nonisolated static var videoResolution: String {
        UserDefaults.standard.string(forKey: videoResolutionKey) ?? "original"
    }

    nonisolated static var videoCompress: Bool {
        // default ON: "make the file lighter" is the module's whole point
        UserDefaults.standard.object(forKey: videoCompressKey) as? Bool ?? true
    }

    /// One-time migration of the legacy single "quality" into the split pair.
    nonisolated static func migrateLegacyVideoQuality() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: videoResolutionKey) == nil,
              let legacy = defaults.string(forKey: videoQualityKey)
        else { return }
        defaults.set(legacy == "hevc" ? "original" : legacy, forKey: videoResolutionKey)
        defaults.set(legacy == "hevc", forKey: videoCompressKey)
    }

    nonisolated static func classify(_ url: URL) -> MediaKind {
        if url.pathExtension.lowercased() == "pdf" { return .pdf }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .unsupported }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .unsupported
    }

    // MARK: - Batch

    /// Short side of the largest pending video: resolution chips at or above
    /// it would re-encode at the same frame size — a confusing duplicate of
    /// "squeeze", so the UI hides them. 0 = unknown (still loading).
    var videoMaxShortSide: Int {
        batch.pending(.video).reduce(0) { side, url in
            guard let label = videoResolutions[url.path] else { return side }
            let value = label == "4K" ? 2160 : (Int(label.dropLast()) ?? 0)
            return max(side, value)
        }
    }

    /// "1080p"-style label from the frame's short side.
    nonisolated private static func resolutionLabel(_ size: CGSize) -> String {
        let p = Int(min(abs(size.width), abs(size.height)).rounded())
        return p >= 2100 ? "4K" : "\(p)p"
    }

    /// Reads resolutions of added videos in the background — for the "original (1080p)" label.
    private func loadResolutions(_ urls: [URL]) {
        for url in urls where Self.classify(url) == .video {
            guard videoResolutions[url.path] == nil else { continue }
            Task.detached { [weak self] in
                let asset = AVURLAsset(url: url)
                guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize) else { return }
                let label = Self.resolutionLabel(size)
                await MainActor.run { [weak self] in
                    self?.videoResolutions[url.path] = label
                }
            }
        }
    }

    /// Folders expand into their contents (up to 500 files); duplicates are skipped.
    func addToBatch(_ urls: [URL]) {
        var incoming: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            else { continue }
            if isDirectory.boolValue {
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                var taken = 0
                while taken < 500, let item = enumerator?.nextObject() as? URL {
                    let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
                    if values?.isRegularFile == true {
                        incoming.append(item)
                        taken += 1
                    }
                }
            } else {
                incoming.append(url)
            }
        }
        var seen = Set(batch.all.map(\.url.path))
        loadResolutions(incoming)
        for url in incoming where !seen.contains(url.path) {
            seen.insert(url.path)
            batch.append(url, kind: Self.classify(url))
        }
        lastResult = nil
        for kind in [MediaKind.image, .pdf, .video, .audio] {
            scheduleEstimate(kind)
        }
    }

    /// "Clear finished" button: drops the checked-off ones, the rest stays put.
    func clearDone() {
        batch.clearDone()
    }

    func clearBatch() {
        batch = Batch()
        fileEstimates = [:]
        lastResult = nil
    }

    // MARK: - Conversion

    func convert(_ kind: MediaKind) {
        guard !busy, kind != .unsupported else { return }
        let files = batch.pending(kind) // only not-yet-converted files
        guard !files.isEmpty else { return }
        busy = true
        activeKind = kind
        lastResult = nil
        let format = Self.format
        let scale = Self.scale
        let quality = Self.quality(for: kind)
        let videoFormat = Self.videoFormat
        let videoResolution = Self.videoResolution
        let videoCompress = Self.videoCompress
        let destination = Self.destinationDirectory

        Task.detached(priority: .userInitiated) { [weak self] in
            var converted = 0
            var savedBytes: Int64 = 0
            var failedURLs: Set<URL> = []
            var done = Set<URL>()
            let total = files.count
            for (index, url) in files.enumerated() {
                await MainActor.run { [weak self] in
                    self?.progress = "\(index + 1)/\(total)"
                    self?.batchFraction = Double(index) / Double(total)
                }
                let outDir = destination ?? url.deletingLastPathComponent()
                let originalSize = (try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                let outURL: URL?
                switch kind {
                case .image:
                    outURL = Self.convertImage(url, to: outDir, format: format, scale: scale, quality: quality)
                case .pdf:
                    // scale applies to images only; PDF is squeezed via quality
                    outURL = Self.compressPDF(url, to: outDir, scale: 1.0, quality: quality)
                case .video:
                    let report: @Sendable (Double) -> Void = { [weak self] fraction in
                        Task { @MainActor in
                            self?.fileFraction = fraction
                            self?.batchFraction = (Double(index) + fraction) / Double(total)
                        }
                    }
                    outURL = await Self.convertVideo(
                        url, to: outDir, format: videoFormat,
                        resolution: videoResolution, compress: videoCompress,
                        onProgress: report)
                    await MainActor.run { [weak self] in self?.fileFraction = nil }
                case .audio:
                    outURL = await Self.convertAudio(url, to: outDir)
                case .unsupported:
                    outURL = nil
                }
                if let outURL {
                    converted += 1
                    done.insert(url)
                    let newSize = (try? FileManager.default
                        .attributesOfItem(atPath: outURL.path)[.size] as? Int64) ?? 0
                    savedBytes += max(0, originalSize - newSize)
                } else if kind != .unsupported {
                    failedURLs.insert(url) // honestly show "failed" instead of staying silent
                }
            }
            let summary = Self.summary(converted: converted, savedBytes: savedBytes)
            let finished = done
            let failures = failedURLs
            let didConvert = converted > 0
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.busy = false
                self.activeKind = nil
                self.progress = nil
                self.batchFraction = nil
                self.lastResult = summary
                // missing key = ON: finished files hide by default
                if UserDefaults.standard.object(forKey: Self.autoClearKey) as? Bool ?? true {
                    self.batch.remove(finished, kind: kind) // auto-clear finished ones
                } else {
                    self.batch.markDone(finished, kind: kind)
                }
                self.batch.markFailed(failures, kind: kind)
                self.scheduleEstimate(kind)
                if didConvert { Sounds.play("Glass", gain: 0.4) }
            }
        }
    }

    /// Recompute the group size estimate. For images and PDFs we convert the
    /// first file into a temp folder and extrapolate; for video/audio — only
    /// the current size (a trial conversion would take too long).
    func scheduleEstimate(_ kind: MediaKind) {
        guard kind != .unsupported else { return }
        let files = batch.pending(kind)
        guard !files.isEmpty else {
            estimates[kind] = nil
            return
        }
        let total = files.reduce(Int64(0)) { sum, url in
            sum + ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
        }
        guard kind == .image || kind == .pdf else {
            // video/audio: the system encoder's own forecast
            // (estimatedOutputFileLength) — honest and responsive to settings
            let token = UUID()
            estimateTokens[kind] = token
            let sample = files[0]
            let videoFormat = Self.videoFormat
            let videoResolution = Self.videoResolution
            let videoCompress = Self.videoCompress
            estimates[kind] = Self.sizeText(total) // while computing — show the current size
            Task.detached(priority: .utility) { [weak self] in
                let estimate: Int64?
                if kind == .video {
                    estimate = await Self.estimatedVideoSize(
                        sample, format: videoFormat,
                        resolution: videoResolution, compress: videoCompress)
                } else {
                    estimate = await Self.estimatedAudioSize(sample)
                }
                guard let estimate, estimate > 0,
                      let sampleSize = try? FileManager.default
                          .attributesOfItem(atPath: sample.path)[.size] as? Int64,
                      sampleSize > 0
                else { return }
                let projected = Int64(Double(total) * Double(estimate) / Double(sampleSize))
                let text = "\(Self.sizeText(total)) → ~\(Self.sizeText(projected))"
                let ratio = Double(estimate) / Double(sampleSize)
                await MainActor.run { [weak self] in
                    guard let self, self.estimateTokens[kind] == token else { return }
                    self.estimates[kind] = text
                    self.applyFileEstimates(kind, ratio: ratio)
                }
            }
            return
        }
        let sample = files[0]
        let format = kind == .image ? Self.format : "pdf"
        let scale = kind == .image ? Self.scale : 1.0
        let qualityPercent = Int((Self.quality(for: kind) * 100).rounded())

        // curve is current — instant interpolation with no work at all
        if let curve = curves[kind],
           curve.samplePath == sample.path, curve.format == format,
           curve.scale == scale, curve.totalBytes == total {
            estimates[kind] = Self.interpolated(curve: curve, quality: qualityPercent)
            applyFileEstimates(kind, ratio: curve.ratio(atQuality: qualityPercent))
            return
        }

        // no curve, or the parameters changed — recompute in the background
        estimates[kind] = Self.sizeText(total)
        let token = UUID()
        estimateTokens[kind] = token
        Task.detached(priority: .utility) { [weak self] in
            guard let sampleSize = try? FileManager.default
                .attributesOfItem(atPath: sample.path)[.size] as? Int64, sampleSize > 0
            else { return }
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hop-estimate-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            var points: [Int: Int64] = [:]
            for q in Self.curveQualities {
                let stillValid = await MainActor.run { [weak self] in
                    self?.estimateTokens[kind] == token
                }
                guard stillValid else { return }
                let outURL: URL?
                if kind == .image {
                    outURL = Self.convertImage(sample, to: tempDir, format: format, scale: scale, quality: Double(q) / 100)
                } else {
                    outURL = Self.compressPDF(sample, to: tempDir, scale: 1.0, quality: Double(q) / 100)
                }
                if let outURL,
                   let size = try? FileManager.default
                       .attributesOfItem(atPath: outURL.path)[.size] as? Int64 {
                    points[q] = size
                }
            }
            guard !points.isEmpty else { return }
            let curve = EstimateCurve(
                samplePath: sample.path, format: format, scale: scale,
                totalBytes: total, sampleBytes: sampleSize, points: points
            )
            await MainActor.run { [weak self] in
                guard let self, self.estimateTokens[kind] == token else { return }
                self.curves[kind] = curve
                let q = Int((Self.quality(for: kind) * 100).rounded())
                self.estimates[kind] = Self.interpolated(curve: curve, quality: q)
                self.applyFileEstimates(kind, ratio: curve.ratio(atQuality: q))
            }
        }
    }

    /// "current → ~projected" for each pending file in the group: files vary
    /// in size, so the group forecast is spread via the compression ratio.
    private func applyFileEstimates(_ kind: MediaKind, ratio: Double) {
        guard ratio > 0 else { return }
        for file in batch.files(kind) where !file.done && file.bytes > 0 {
            let projected = Int64(Double(file.bytes) * ratio)
            fileEstimates[file.url.path] =
                "\(Self.sizeText(file.bytes)) → ~\(Self.sizeText(projected))"
        }
    }

    /// "current → ~projected" via the curve's math (HopCore).
    nonisolated private static func interpolated(curve: EstimateCurve, quality: Int) -> String {
        guard let projected = curve.projectedTotal(atQuality: quality) else {
            return sizeText(curve.totalBytes)
        }
        return "\(sizeText(curve.totalBytes)) → ~\(sizeText(projected))"
    }

    nonisolated static func sizeText(_ bytes: Int64) -> String {
        SizeFormatting.sizeText(bytes)
    }

    // MARK: - Mechanics (off the main thread)

    nonisolated private static func uniqueURL(_ dir: URL, name: String, ext: String) -> URL {
        var candidate = dir.appendingPathComponent("\(name)-min.\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name)-min-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    nonisolated private static func utType(for format: String) -> (UTType, String) {
        switch format {
        case "png": return (.png, "png")
        case "heic": return (.heic, "heic")
        case "avif":
            if let avif = UTType("public.avif") { return (avif, "avif") }
            return (.jpeg, "jpg")
        default: return (.jpeg, "jpg")
        }
    }

    nonisolated private static func convertImage(
        _ url: URL, to dir: URL, format: String, scale: Double, quality: Double
    ) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let width = props[kCGImagePropertyPixelWidth] as? Double ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Double ?? 0
        let maxSide = max(width, height) * scale

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(16, maxSide),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
        else { return nil }

        let (type, ext) = utType(for: format)
        let outURL = uniqueURL(dir, name: url.deletingPathExtension().lastPathComponent, ext: ext)
        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL, type.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
            // metadata trace: who recompressed the file
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: "Hop"],
        ] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? outURL : nil
    }

    /// Re-render pages with JPEG compression — the standard way to shrink scans.
    nonisolated private static func compressPDF(
        _ url: URL, to dir: URL, scale: Double, quality: Double
    ) -> URL? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        let outURL = uniqueURL(dir, name: url.deletingPathExtension().lastPathComponent, ext: "pdf")
        var mediaBox = CGRect.zero
        let info = [kCGPDFContextCreator: "Hop"] as CFDictionary
        guard let ctx = CGContext(outURL as CFURL, mediaBox: nil, info) else { return nil }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            // render at ~150dpi × scale — a balance of readability and size
            let pixelWidth = bounds.width / 72 * 150 * scale
            let renderScale = max(0.2, pixelWidth / bounds.width)
            let size = NSSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]),
                  let jpegSource = CGImageSourceCreateWithData(jpeg as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(jpegSource, 0, nil)
            else { continue }

            mediaBox = CGRect(origin: .zero, size: bounds.size)
            ctx.beginPage(mediaBox: &mediaBox)
            ctx.draw(cgImage, in: mediaBox)
            ctx.endPage()
        }
        ctx.closePDF()
        return FileManager.default.fileExists(atPath: outURL.path) ? outURL : nil
    }

    /// Video: recompression/conversion via the system encoder.
    /// "Original" quality re-encodes too — heavy sources slim down.
    /// The codec choice is the preset; the resolution is our own
    /// videoComposition. The resolution presets (1920x1080 etc.) fit the
    /// video into a LANDSCAPE box — a vertical 1244×1664 came out 807×1080
    /// instead of 1080×1444, so "1080p" (by the short side) was a lie.
    nonisolated private static func presetName(compress: Bool) -> String {
        compress ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
    }

    /// Downscale to a target SHORT side, aspect ratio and orientation kept
    /// (vertical stays vertical). nil = source is already at or below the
    /// target, or the resolution is "original" — no composition needed.
    nonisolated private static func scaleComposition(
        asset: AVAsset, resolution: String
    ) async -> AVMutableVideoComposition? {
        guard let targetShortSide = Double(resolution) else { return nil }
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let width = abs(oriented.width)
        let height = abs(oriented.height)
        guard width > 0, height > 0 else { return nil }
        let scale = targetShortSide / min(width, height)
        guard scale < 1 else { return nil } // never upscale
        let composition = AVMutableVideoComposition()
        // encoders want even dimensions
        composition.renderSize = CGSize(
            width: (width * scale / 2).rounded() * 2,
            height: (height * scale / 2).rounded() * 2
        )
        let fps = (try? await track.load(.nominalFrameRate)) ?? 30
        composition.frameDuration = CMTime(
            value: 1, timescale: CMTimeScale(max(1, fps.rounded()))
        )
        let duration = (try? await asset.load(.duration)) ?? .positiveInfinity
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        // orientation first (origin pulled back to zero — rotation transforms
        // shift it negative), then the downscale
        let normalized = transform.concatenating(
            CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY)
        )
        layer.setTransform(
            normalized.concatenating(CGAffineTransform(scaleX: scale, y: scale)),
            at: .zero
        )
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }

    /// Size forecast by a real sample encode: the first seconds go through the
    /// actual export preset and the result extrapolates by duration. Bitrate
    /// tables drifted 20%+ from the encoder on real footage — measuring the
    /// encoder itself is the only honest number.
    nonisolated private static func estimatedVideoSize(
        _ url: URL, format: String, resolution: String, compress: Bool
    ) async -> Int64? {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds > 0
        else { return nil }
        let originalBytes = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        // original size without compression = container change only, size is almost the same
        guard resolution != "original" || compress else { return originalBytes }
        guard let session = AVAssetExportSession(
            asset: asset, presetName: presetName(compress: compress))
        else { return nil }
        session.videoComposition = await scaleComposition(asset: asset, resolution: resolution)
        let sampleSeconds = min(8.0, seconds)
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: sampleSeconds, preferredTimescale: 600)
        )
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hop-estimate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let ext = format == "mov" ? "mov" : "mp4"
        let type: AVFileType = format == "mov" ? .mov : .mp4
        let outURL = tempDir.appendingPathComponent("sample.\(ext)")
        guard let exported = await export(session, to: outURL, as: type),
              let sampleBytes = try? FileManager.default
                  .attributesOfItem(atPath: exported.path)[.size] as? Int64,
              sampleBytes > 0
        else { return nil }
        let projected = Int64(Double(sampleBytes) * seconds / sampleSeconds)
        // if the source is already lighter than the target, compression must not inflate it
        return (originalBytes > 0 && projected > originalBytes) ? originalBytes : projected
    }

    /// M4A AAC ~128 kbit/s × duration.
    nonisolated private static func estimatedAudioSize(_ url: URL) async -> Int64? {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds > 0
        else { return nil }
        let originalBytes = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let projected = Int64(128_000.0 * seconds / 8)
        return (originalBytes > 0 && projected > originalBytes) ? originalBytes : projected
    }

    nonisolated private static func convertVideo(
        _ url: URL, to dir: URL, format: String, resolution: String, compress: Bool,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName(compress: compress))
        else { return nil }
        session.videoComposition = await scaleComposition(asset: asset, resolution: resolution)
        let ext = format == "mov" ? "mov" : "mp4"
        let type: AVFileType = format == "mov" ? .mov : .mp4
        let outURL = uniqueURL(dir, name: url.deletingPathExtension().lastPathComponent, ext: ext)
        return await export(session, to: outURL, as: type, onProgress: onProgress)
    }

    /// Audio: anything the system can read (MP3/WAV/FLAC/AAC…) → M4A (AAC).
    nonisolated private static func convertAudio(_ url: URL, to dir: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { return nil }
        let outURL = uniqueURL(dir, name: url.deletingPathExtension().lastPathComponent, ext: "m4a")
        return await export(session, to: outURL, as: .m4a)
    }

    nonisolated private static func export(
        _ session: AVAssetExportSession, to outURL: URL, as type: AVFileType,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        let software = AVMutableMetadataItem()
        software.identifier = .commonIdentifierSoftware
        software.value = "Hop" as NSString
        session.metadata = [software]
        // the encoder knows its own progress — poll it while it works
        let poller = onProgress.map { report in
            Task.detached { [weak session] in
                while let session, !Task.isCancelled {
                    report(Double(session.progress))
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
        defer { poller?.cancel() }
        if #available(macOS 15, *) {
            do {
                try await session.export(to: outURL, as: type)
            } catch {
                return nil
            }
        } else {
            session.outputURL = outURL
            session.outputFileType = type
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else { return nil }
        }
        return FileManager.default.fileExists(atPath: outURL.path) ? outURL : nil
    }

    nonisolated private static var destinationDirectory: URL? {
        let dest = UserDefaults.standard.string(forKey: destKey) ?? "downloads"
        switch dest {
        case "same":
            return nil // next to the source file
        case "custom":
            if let path = UserDefaults.standard.string(forKey: destPathKey) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        default:
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
    }

    nonisolated private static func summary(converted: Int, savedBytes: Int64) -> String {
        guard converted > 0 else { return "—" }
        let mb = Double(savedBytes) / 1_000_000
        if mb >= 1 {
            return "✓ \(converted) · −\(String(format: "%.1f", mb)) MB"
        }
        return "✓ \(converted)"
    }
}
