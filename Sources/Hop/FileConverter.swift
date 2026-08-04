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
    nonisolated static let videoFormatKey = "convVideoFormat" // original | mp4 | mov
    /// Legacy single "quality" (original | hevc | 1080 | 720 | 540) —
    /// migrated into resolution + compress on init, read-only since.
    nonisolated static let videoQualityKey = "convVideoQuality"
    nonisolated static let videoResolutionKey = "convVideoResolution" // original | 2160 | 1080 | 720 | 540
    nonisolated static let videoCompressKey = "convVideoCompress" // HEVC instead of H.264
    /// The SHAPE a platform expects (`VideoFrame.Shape`), independent of the
    /// resolution above: a reel is 9:16 whether it is 1080 or 720 tall.
    nonisolated static let videoShapeKey = "convVideoShape"        // source | vertical | portrait | square | landscape
    /// What happens to a picture whose own shape does not match the frame
    /// (`VideoFrame.Fit`): fill and crop, pad, or pad over a blurred copy.
    nonisolated static let videoFitKey = "convVideoFit"            // fill | pad | blur
    /// How hard the encoder squeezes when compression is on: 10…100, the same
    /// scale the image and PDF sliders use.
    nonisolated static let videoQualityLevelKey = "convVideoQualityLevel"
    nonisolated static let autoClearKey = "convAutoClear"       // finished ones disappear on their own
    /// Documents: what the group is converted INTO (pdf | md | docx).
    nonisolated static let docTargetKey = "convDocTarget"
    /// PDFs have two jobs now: squeeze the file (default) or pull its text out
    /// as markdown. A mode rather than a category, so a dropped PDF still lands
    /// in the group the user expects.
    nonisolated static let pdfModeKey = "convPdfMode"           // compress | markdown

    enum MediaKind: Sendable {
        case image, pdf, video, audio, document, unsupported
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
        var documents: [BatchFile] = []
        var unsupported: [BatchFile] = []

        var all: [BatchFile] { images + pdfs + videos + audios + documents + unsupported }
        var isEmpty: Bool { all.isEmpty }

        func files(_ kind: MediaKind) -> [BatchFile] {
            switch kind {
            case .image: return images
            case .pdf: return pdfs
            case .video: return videos
            case .audio: return audios
            case .document: return documents
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
            case .document: documents.append(file)
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
            case .document: strip(&documents)
            case .unsupported: strip(&unsupported)
            }
        }

        /// Drop everything finished from every group.
        mutating func clearDone() {
            images.removeAll(where: \.done)
            pdfs.removeAll(where: \.done)
            videos.removeAll(where: \.done)
            audios.removeAll(where: \.done)
            documents.removeAll(where: \.done)
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
            case .document: mark(&documents)
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
            case .document: mark(&documents)
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
    /// The frame size of each added video, oriented the way it plays. The label
    /// above is derived from it; the row also needs the two sides themselves to
    /// work out what the current settings will produce.
    @Published private(set) var videoSizes: [String: CGSize] = [:]
    @Published private(set) var lastResult: String?
    /// When the bar last published a value. The video encoder reports every
    /// sample — thirty times a second — and a bar told to animate to a new
    /// value that often never finishes a move, so it looked stuck a few percent
    /// in while the percentage beside it ran to a hundred (Anton, 2026-08-04).
    private var lastProgressAt = Date.distantPast

    /// The file the last conversion produced — what the reveal button opens.
    /// Kept as a URL rather than a folder so Finder can select it: "where did
    /// it go" is answered better by the file being highlighted than by a folder
    /// of a hundred things (Anton, 2026-08-04).
    @Published private(set) var lastOutput: URL?
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

    /// What documents are converted into; pdf unless the user says otherwise.
    nonisolated static var docTarget: DocumentConversion.Target {
        DocumentConversion.Target(rawValue: UserDefaults.standard.string(forKey: docTargetKey) ?? "")
            ?? .pdf
    }

    /// What a PDF group does with its files: nil squeezes them, a target
    /// extracts their text into that format. Word matters as much as markdown
    /// here — a pdf that has to be edited usually has to be edited in Word
    /// (Anton, 2026-07-29).
    nonisolated static var pdfTextTarget: DocumentConversion.Target? {
        switch UserDefaults.standard.string(forKey: pdfModeKey) {
        case "markdown": return .markdown
        case "docx": return .docx
        default: return nil
        }
    }

    /// Whether a PDF group squeezes its files or extracts their text.
    nonisolated static var pdfExtractsText: Bool { pdfTextTarget != nil }

    /// Default "original": a container change nobody asked for is not a
    /// conversion — mp4 in, mp4 out, and the choice is there for when it is
    /// actually wanted (Anton, 2026-08-04).
    nonisolated static var videoFormat: String {
        UserDefaults.standard.string(forKey: videoFormatKey) ?? "original"
    }

    /// Which container the format row highlights. Until the user picks one it
    /// is whatever the pending files already are — there is no "original" chip,
    /// because a person looking at the row wants to read the ANSWER, not a
    /// setting that stands for one (Anton, 2026-08-04). A format the system
    /// cannot write reads as mp4, which is what it will become.
    var highlightedVideoFormat: String {
        let setting = Self.videoFormat
        guard setting == "original" else { return setting }
        guard let first = batch.pending(.video).first ?? batch.videos.first?.url else { return "mp4" }
        return Self.videoContainer(for: first, setting: "original")
    }

    /// The container a given file will be written into: whatever was chosen, or
    /// the source's own when that is "original". Anything the system cannot
    /// write (avi, mkv) lands in mp4.
    nonisolated static func videoContainer(for url: URL, setting: String) -> String {
        guard setting == "original" else { return setting == "mov" ? "mov" : "mp4" }
        return url.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
    }

    nonisolated static var videoResolution: String {
        UserDefaults.standard.string(forKey: videoResolutionKey) ?? "original"
    }

    nonisolated static var videoCompress: Bool {
        // default ON: "make the file lighter" is the module's whole point
        UserDefaults.standard.object(forKey: videoCompressKey) as? Bool ?? true
    }

    /// Default: leave the picture the shape it already is. Reshaping a video is
    /// something to ask for, never something to do to somebody's file quietly.
    nonisolated static var videoShape: VideoFrame.Shape {
        UserDefaults.standard.string(forKey: videoShapeKey)
            .flatMap(VideoFrame.Shape.init(rawValue:)) ?? .source
    }

    /// How hard to squeeze, 0…1. Default 0.55: visibly lighter files that still
    /// hold up full-screen, the same middle the image slider sits at.
    nonisolated static var videoQuality: Double {
        Double((UserDefaults.standard.object(forKey: videoQualityLevelKey) as? Int) ?? 55) / 100
    }

    /// Default: fill the frame. It is what every other tool does and what a
    /// platform shows anyway — a padded video posted as a reel gets bars.
    nonisolated static var videoFit: VideoFrame.Fit {
        UserDefaults.standard.string(forKey: videoFitKey)
            .flatMap(VideoFrame.Fit.init(rawValue:)) ?? .fill
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
        // documents are matched by extension: .md and .txt also conform to
        // public.text, which would otherwise fall through as unsupported
        if DocumentConversion.readableExtensions.contains(url.pathExtension.lowercased()) {
            return .document
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .unsupported }
        if type.conforms(to: .image) { return .image }
        // The system says what it can open, rather than a list kept here: mkv,
        // webm, wmv and flv all classify as movies and cannot be read at all,
        // so they used to land in the video group and fail at convert time with
        // nothing said in advance (Anton, 2026-08-04). Named as unsupported on
        // arrival, they are answered honestly by the drop itself.
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return systemCanRead(type) ? .video : .unsupported
        }
        if type.conforms(to: .audio) { return systemCanRead(type) ? .audio : .unsupported }
        return .unsupported
    }

    /// Whether AVFoundation is prepared to open this type at all. Asked of the
    /// system so the answer stays right as macOS gains and loses formats.
    private nonisolated static func systemCanRead(_ type: UTType) -> Bool {
        AVURLAsset.audiovisualTypes().contains { $0.rawValue == type.identifier }
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

    /// What the current settings will make of a video: "720p → 404p", or just
    /// "720p" when nothing about the frame is changing. The row used to show the
    /// source's own resolution and nothing else, so picking 540p left "718p"
    /// standing over it (Anton, 2026-08-04).
    func resolutionTransition(_ url: URL) -> String? {
        guard let source = videoResolutions[url.path] else { return nil }
        guard let size = videoSizes[url.path] else { return source }
        let layout = VideoFrame.layout(
            sourceWidth: Double(size.width), sourceHeight: Double(size.height),
            shape: Self.videoShape, shortSide: Double(Self.videoResolution),
            fit: Self.videoFit)
        guard let layout else { return source }
        let result = Self.resolutionLabel(CGSize(width: layout.width, height: layout.height))
        return result == source ? source : "\(source) → \(result)"
    }

    /// "1080p"-style label from the frame's short side.
    nonisolated static func resolutionLabel(_ size: CGSize) -> String {
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
                // a rotated track plays at its transformed size, and that is
                // the one a person means by "720p"
                let transform = (try? await track.load(.preferredTransform)) ?? .identity
                let oriented = CGRect(origin: .zero, size: size).applying(transform)
                let playing = CGSize(width: abs(oriented.width), height: abs(oriented.height))
                let label = Self.resolutionLabel(playing)
                await MainActor.run { [weak self] in
                    self?.videoResolutions[url.path] = label
                    self?.videoSizes[url.path] = playing
                }
            }
        }
    }

    /// Moves the bar, at most ten times a second. The end of a file and the end
    /// of the batch are always published, so the bar never stops short.
    private func publishProgress(file: Double?, batch: Double, force: Bool = false) {
        let now = Date()
        guard force || batch >= 1 || now.timeIntervalSince(lastProgressAt) >= 0.1 else { return }
        lastProgressAt = now
        fileFraction = file
        batchFraction = batch
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
        for kind in [MediaKind.image, .pdf, .video, .audio, .document] {
            scheduleEstimate(kind)
        }
    }

    /// Ingest whatever the pasteboard holds, mirroring a drop onto the convert
    /// zone: file URLs (a Finder copy) go straight to `addToBatch`; a raw image
    /// with no backing file — a screenshot copied to the clipboard — is written
    /// to a temp file first so the SAME file-based batch path handles it. There
    /// is no second pipeline: both routes end at `addToBatch`. Returns true when
    /// something convertible was found; text-only or an empty pasteboard is a
    /// silent no-op (returns false) so the caller can skip opening the window.
    @discardableResult
    func addFromPasteboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        // File URLs first — identical to a Finder drop. Directories expand
        // inside `addToBatch`; unsupported files land in its "unsupported"
        // bucket exactly as a dropped file of the same type would.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            addToBatch(urls)
            return true
        }
        // A raw image (screenshot on the clipboard, no file): materialize it.
        if let url = Self.materializePasteboardImage(pasteboard) {
            addToBatch([url])
            return true
        }
        return false
    }

    /// Writes a pasteboard image to a temp file so `addToBatch` treats it like
    /// any other file. Keeps the original bytes when the clipboard already has
    /// PNG or TIFF (screenshots do), re-encoding only as a last resort. Nil when
    /// the pasteboard carries no image.
    nonisolated private static func materializePasteboardImage(_ pasteboard: NSPasteboard) -> URL? {
        let data: Data
        let ext: String
        if let png = pasteboard.data(forType: .png) {
            data = png; ext = "png"
        } else if let tiff = pasteboard.data(forType: .tiff) {
            data = tiff; ext = "tiff"
        } else if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation {
            data = tiff; ext = "tiff"
        } else {
            return nil
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hop-paste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A readable, unique name — the batch row shows the last path component.
        let url = dir.appendingPathComponent("pasted-image-\(UUID().uuidString.prefix(8)).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
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
        let videoShape = Self.videoShape
        let videoFit = Self.videoFit
        let videoQuality = Self.videoQuality
        let docTarget = Self.docTarget
        let pdfTextTarget = Self.pdfTextTarget
        let destination = Self.destinationDirectory

        Task.detached(priority: .userInitiated) { [weak self] in
            var converted = 0
            var savedBytes: Int64 = 0
            var failedURLs: Set<URL> = []
            var done = Set<URL>()
            let total = files.count
            // The bar moves by BYTES, not by file count. Counting files made a
            // batch of one jump straight from nothing to everything, and a big
            // file among small ones sat still and then leapt (Anton, 2026-08-04).
            let weights = files.map { url in
                Double((try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0) + 1
            }
            let weightTotal = weights.reduce(0, +)
            var weightDone: Double = 0
            for (index, url) in files.enumerated() {
                // this file's slice of the bar, fixed before the work starts so
                // the progress closure has nothing mutable to reach for
                let base = weightDone
                let slice = weights[index]
                let atFileStart = weightTotal > 0 ? base / weightTotal : 0
                await MainActor.run { [weak self] in
                    self?.progress = "\(index + 1)/\(total)"
                    self?.batchFraction = atFileStart
                }
                let outDir = destination ?? url.deletingLastPathComponent()
                let originalSize = (try? FileManager.default
                    .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                let outURL: URL?
                // every kind that can say where it is reports through this
                let report: @Sendable (Double) -> Void = { [weak self] within in
                    let value = weightTotal > 0
                        ? min(1, (base + slice * within) / weightTotal)
                        : 0
                    Task { @MainActor in
                        self?.publishProgress(file: within, batch: value)
                    }
                }
                switch kind {
                case .image:
                    outURL = Self.convertImage(url, to: outDir, format: format, scale: scale, quality: quality)
                case .pdf:
                    if let target = pdfTextTarget {
                        outURL = await Self.convertDocument(url, to: outDir, target: target)
                    } else {
                        // scale applies to images only; PDF is squeezed via quality
                        outURL = Self.compressPDF(url, to: outDir, scale: 1.0, quality: quality,
                                                  onProgress: report)
                    }
                case .video:
                    outURL = await Self.convertVideo(
                        url, to: outDir, format: videoFormat,
                        resolution: videoResolution, compress: videoCompress,
                        shape: videoShape, fit: videoFit, quality: videoQuality,
                        onProgress: report)
                    await MainActor.run { [weak self] in self?.fileFraction = nil }
                case .audio:
                    outURL = await Self.convertAudio(url, to: outDir)
                case .document:
                    outURL = await Self.convertDocument(url, to: outDir, target: docTarget)
                case .unsupported:
                    outURL = nil
                }
                weightDone += weights[index]
                // a finished file lands on the bar whole, whatever the throttle
                // was in the middle of
                let atFileEnd = weightTotal > 0 ? weightDone / weightTotal : 1
                await MainActor.run { [weak self] in
                    self?.publishProgress(file: nil, batch: atFileEnd, force: true)
                }
                if let outURL {
                    converted += 1
                    done.insert(url)
                    await MainActor.run { [weak self] in self?.lastOutput = outURL }
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
                if didConvert { Sounds.converted() }
            }
        }
    }

    /// Recompute the group size estimate. For images and PDFs we convert the
    /// first file into a temp folder and extrapolate; for video/audio — only
    /// the current size (a trial conversion would take too long).
    func scheduleEstimate(_ kind: MediaKind) {
        // documents change SHAPE, not weight — a size forecast would be noise
        guard kind != .unsupported, kind != .document else {
            estimates[kind] = nil
            return
        }
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
            let videoShape = Self.videoShape
            let videoFit = Self.videoFit
            let videoQuality = Self.videoQuality
            estimates[kind] = Self.sizeText(total) // while computing — show the current size
            Task.detached(priority: .utility) { [weak self] in
                let estimate: Int64?
                if kind == .video {
                    estimate = await Self.estimatedVideoSize(
                        sample, format: videoFormat,
                        resolution: videoResolution, compress: videoCompress,
                        shape: videoShape, fit: videoFit, quality: videoQuality)
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

    /// One document into another. The heavy lifting lives in
    /// DocumentConversion; this only picks the direction and the output name.
    /// A file already in the target format is REWRITTEN rather than refused —
    /// markdown through our parser comes back normalized, and a Word file comes
    /// back as a clean document, which is a reasonable thing to ask for.
    /// Main-actor: AppKit's document readers and its pagination machinery both
    /// belong there. Only PDF text extraction (PDFKit + Vision, and slow on a
    /// scan) is pushed off to a detached task.
    @MainActor
    private static func convertDocument(
        _ url: URL, to dir: URL, target: DocumentConversion.Target
    ) async -> URL? {
        let name = url.deletingPathExtension().lastPathComponent
        // documents keep their own name: "-min" belongs to the compression
        // story, and "notes-min.pdf" would be a lie about what happened
        let outURL = uniqueURL(dir, name: name, ext: target.fileExtension, suffix: "")
        switch target {
        case .markdown:
            let text: String?
            if url.pathExtension.lowercased() == "pdf" {
                text = await Task.detached { DocumentConversion.markdown(fromPDF: url) }.value
            } else if let attributed = DocumentConversion.read(url) {
                text = DocumentConversion.markdown(from: attributed)
            } else {
                text = nil
            }
            guard let text, (try? text.write(to: outURL, atomically: true, encoding: .utf8)) != nil
            else { return nil }
            return outURL
        case .pdf:
            guard let attributed = DocumentConversion.read(url) else { return nil }
            return DocumentConversion.writePDF(attributed, to: outURL) ? outURL : nil
        case .docx:
            // A PDF has no reader of its own — its text is extracted the way the
            // markdown target extracts it, then laid out again as a document.
            let attributed: NSAttributedString?
            if url.pathExtension.lowercased() == "pdf" {
                let text = await Task.detached { DocumentConversion.markdown(fromPDF: url) }.value
                attributed = text.map { DocumentConversion.attributed(markdown: $0) }
            } else {
                attributed = DocumentConversion.read(url)
            }
            guard let attributed, DocumentConversion.writeDocx(attributed, to: outURL)
            else { return nil }
            return outURL
        }
    }

    nonisolated private static func uniqueURL(
        _ dir: URL, name: String, ext: String, suffix: String = "-min"
    ) -> URL {
        var candidate = dir.appendingPathComponent("\(name)\(suffix).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name)\(suffix)-\(index).\(ext)")
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
        _ url: URL, to dir: URL, scale: Double, quality: Double,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> URL? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }
        let outURL = uniqueURL(dir, name: url.deletingPathExtension().lastPathComponent, ext: "pdf")
        var mediaBox = CGRect.zero
        let info = [kCGPDFContextCreator: "Hop"] as CFDictionary
        guard let ctx = CGContext(outURL as CFURL, mediaBox: nil, info) else { return nil }

        for index in 0..<document.pageCount {
            // a hundred-page file takes a while, and a bar that only moves when
            // the whole file is done says nothing while it does
            onProgress?(Double(index) / Double(document.pageCount))
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

    /// The picture placed into the frame the user asked for: a downscale to a
    /// target SHORT side with the shape left alone, or one of the platform
    /// shapes (9:16, 4:5, 1:1, 16:9) with the picture filled, padded or padded
    /// over a blurred copy of itself. nil = nothing to do, and the file goes
    /// through the encoder untouched in shape and size.
    nonisolated private static func frameComposition(
        asset: AVAsset, resolution: String, shape: VideoFrame.Shape, fit: VideoFrame.Fit
    ) async -> AVVideoComposition? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let width = abs(oriented.width)
        let height = abs(oriented.height)
        guard let layout = VideoFrame.layout(
            sourceWidth: Double(width), sourceHeight: Double(height),
            shape: shape, shortSide: Double(resolution), fit: fit
        ) else { return nil }

        let fps = (try? await track.load(.nominalFrameRate)) ?? 30
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps.rounded())))
        let renderSize = CGSize(width: layout.width, height: layout.height)
        // orientation first (origin pulled back to zero — rotation transforms
        // shift it negative), then the scale, then the placement in the frame
        let normalized = transform.concatenating(
            CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY)
        )
        let placed = normalized
            .concatenating(CGAffineTransform(scaleX: layout.scale, y: layout.scale))
            .concatenating(CGAffineTransform(translationX: layout.offsetX, y: layout.offsetY))

        if fit == .blur, layout.hasEmptySpace {
            return await blurredComposition(
                asset: asset, renderSize: renderSize, frameDuration: frameDuration,
                orientation: normalized, layout: layout,
                sourceWidth: Double(width), sourceHeight: Double(height))
        }

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = frameDuration
        let duration = (try? await asset.load(.duration)) ?? .positiveInfinity
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        // padding shows through as the frame's own background, which is black
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(placed, at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }

    /// The padded frame with the empty space filled by an enlarged, blurred copy
    /// of the picture itself — the treatment a vertical feed expects of footage
    /// that was shot wide. Every frame goes through Core Image, so this is the
    /// slow one of the three and is only ever built when there is space to fill.
    nonisolated private static func blurredComposition(
        asset: AVAsset, renderSize: CGSize, frameDuration: CMTime,
        orientation: CGAffineTransform, layout: VideoFrame.Layout,
        sourceWidth: Double, sourceHeight: Double
    ) async -> AVVideoComposition? {
        // the background is the same picture scaled to COVER the frame
        let cover = max(layout.width / sourceWidth, layout.height / sourceHeight)
        let coverOffset = CGPoint(x: (layout.width - sourceWidth * cover) / 2,
                                  y: (layout.height - sourceHeight * cover) / 2)
        let frame = CGRect(origin: .zero, size: renderSize)
        // enough blur that no detail survives to compete with the picture, and
        // scaled to the frame so a 4K export is not blurred less than a 540p one
        let radius = min(renderSize.width, renderSize.height) * 0.05
        let placement = layout
        let composition = try? await AVVideoComposition.videoComposition(
            with: asset
        ) { request in
            let source = request.sourceImage.transformed(by: orientation)
            let background = source
                .transformed(by: CGAffineTransform(scaleX: cover, y: cover))
                .transformed(by: CGAffineTransform(translationX: coverOffset.x, y: coverOffset.y))
                // clamped first: a blur reads pixels beyond the edge, and without
                // this the frame gets a transparent halo around its border
                .clampedToExtent()
                .applyingGaussianBlur(sigma: radius)
                .cropped(to: frame)
            let foreground = source
                .transformed(by: CGAffineTransform(scaleX: placement.scale, y: placement.scale))
                .transformed(by: CGAffineTransform(translationX: placement.offsetX,
                                                   y: placement.offsetY))
            request.finish(with: foreground.composited(over: background).cropped(to: frame),
                           context: nil)
        }
        guard let composition = composition?.mutableCopy() as? AVMutableVideoComposition else {
            return nil
        }
        composition.renderSize = renderSize
        composition.frameDuration = frameDuration
        return composition
    }

    /// Size forecast by a real sample encode: the first seconds go through the
    /// actual export preset and the result extrapolates by duration. Bitrate
    /// tables drifted 20%+ from the encoder on real footage — measuring the
    /// encoder itself is the only honest number.
    /// What the encode will weigh, worked out from the bitrate it will be given
    /// rather than by encoding eight seconds and multiplying. The trial encode
    /// was both slow and, with the system's "highest quality" presets, wrong:
    /// it forecast the original size no matter where the settings stood.
    nonisolated private static func estimatedVideoSize(
        _ url: URL, format: String, resolution: String, compress: Bool,
        shape: VideoFrame.Shape, fit: VideoFrame.Fit, quality: Double
    ) async -> Int64? {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds > 0
        else { return nil }
        let originalBytes = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return originalBytes }

        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let source = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let layout = VideoFrame.layout(
            sourceWidth: Double(source.width), sourceHeight: Double(source.height),
            shape: shape, shortSide: Double(resolution), fit: fit)
        // nothing to re-encode and nothing to reframe: the container changes and
        // the bytes travel across untouched
        if !compress, layout == nil { return originalBytes }

        let width = layout?.width ?? Double(source.width)
        let height = layout?.height ?? Double(source.height)
        let fps = Double((try? await track.load(.nominalFrameRate)) ?? 30)
        let bitrate = VideoBitrate.bitsPerSecond(
            width: width, height: height, fps: fps > 0 ? fps : 30,
            codec: compress ? .hevc : .h264, quality: compress ? quality : 1)
        let hasAudio = (try? await asset.loadTracks(withMediaType: .audio).first) != nil
        let projected = VideoBitrate.projectedBytes(
            seconds: seconds, videoBitsPerSecond: bitrate,
            audioBitsPerSecond: hasAudio ? VideoBitrate.audioBitsPerSecond : 0)
        return VideoBitrate.honestProjection(projected: projected, original: originalBytes)
    }

    nonisolated private static func estimatedAudioSize(_ url: URL) async -> Int64? {
        let asset = AVURLAsset(url: url)
        guard let seconds = try? await asset.load(.duration).seconds, seconds > 0
        else { return nil }
        let originalBytes = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let projected = Int64(128_000.0 * seconds / 8)
        return (originalBytes > 0 && projected > originalBytes) ? originalBytes : projected
    }

    #if DEBUG
    /// The real video path, reachable from the dev self-test entry point.
    nonisolated static func reframeForSelfTest(
        _ url: URL, to dir: URL, shape: VideoFrame.Shape, fit: VideoFrame.Fit,
        compress: Bool? = nil, quality: Double? = nil
    ) async -> URL? {
        await convertVideo(url, to: dir, format: videoFormat, resolution: videoResolution,
                           compress: compress ?? videoCompress, shape: shape, fit: fit,
                           quality: quality ?? videoQuality)
    }

    /// The forecast for one file, for the same dev entry point.
    nonisolated static func estimateForSelfTest(
        _ url: URL, shape: VideoFrame.Shape, fit: VideoFrame.Fit,
        compress: Bool, quality: Double
    ) async -> Int64? {
        await estimatedVideoSize(url, format: videoFormat, resolution: videoResolution,
                                 compress: compress, shape: shape, fit: fit, quality: quality)
    }
    #endif

    nonisolated private static func convertVideo(
        _ url: URL, to dir: URL, format: String, resolution: String, compress: Bool,
        shape: VideoFrame.Shape, fit: VideoFrame.Fit, quality: Double,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        let asset = AVURLAsset(url: url)
        let ext = videoContainer(for: url, setting: format)
        let type: AVFileType = ext == "mov" ? .mov : .mp4
        let outURL = uniqueURL(dir, name: url.deletingPathExtension().lastPathComponent, ext: ext)
        let composition = await frameComposition(
            asset: asset, resolution: resolution, shape: shape, fit: fit)

        // Nothing to change but the container: copy the tracks across instead of
        // re-encoding them. A re-encode at "highest quality" is how this module
        // used to spend a minute producing a file the same size as the original.
        if !compress, composition == nil {
            guard let session = AVAssetExportSession(
                asset: asset, presetName: AVAssetExportPresetPassthrough) else { return nil }
            return await export(session, to: outURL, as: type, onProgress: onProgress)
        }
        return await encodeVideo(
            asset: asset, to: outURL, as: type, composition: composition,
            codec: compress ? .hevc : .h264, quality: compress ? quality : 1,
            onProgress: onProgress)
    }

    /// The encode Hop drives itself, because the system's export presets do not
    /// take a bitrate and a converter without one cannot promise a size. Reader
    /// and writer are wired straight together: frames come out of the source
    /// (through the reframing composition when there is one) and go into an
    /// encoder told exactly how many bits per second to spend.
    nonisolated private static func encodeVideo(
        asset: AVAsset, to outURL: URL, as type: AVFileType,
        composition: AVVideoComposition?, codec: VideoBitrate.Codec, quality: Double,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async -> URL? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform),
              let duration = try? await asset.load(.duration)
        else { return nil }

        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let renderSize = composition?.renderSize
            ?? CGSize(width: abs(oriented.width), height: abs(oriented.height))
        let fps = Double((try? await track.load(.nominalFrameRate)) ?? 30)
        let bitrate = VideoBitrate.bitsPerSecond(
            width: Double(renderSize.width), height: Double(renderSize.height),
            fps: fps > 0 ? fps : 30, codec: codec, quality: quality)

        guard let reader = try? AVAssetReader(asset: asset),
              let writer = try? AVAssetWriter(outputURL: outURL, fileType: type)
        else { return nil }

        // the reader hands over plain pixel buffers; the composition, when there
        // is one, does the reframing on the way out
        let pixelSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ]
        let videoOutput: AVAssetReaderOutput
        if let composition {
            let output = AVAssetReaderVideoCompositionOutput(
                videoTracks: [track], videoSettings: pixelSettings)
            output.videoComposition = composition
            videoOutput = output
        } else {
            videoOutput = AVAssetReaderTrackOutput(track: track, outputSettings: pixelSettings)
        }
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { return nil }
        reader.add(videoOutput)

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
                // two seconds between key frames: seeking stays usable and the
                // bitrate is not eaten by key frames on a static shot
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        // with no composition the picture is untouched, so its rotation has to
        // travel with it rather than be baked in
        if composition == nil { videoInput.transform = transform }
        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)

        // audio, when the file has any, re-encoded to AAC at a plain rate
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: VideoBitrate.audioBitsPerSecond,
            ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioOutput = output
                audioInput = input
            }
        }

        writer.metadata = [softwareTag()]
        guard reader.startReading(), writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)

        let total = duration.seconds
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await pump(videoOutput, into: videoInput, label: "video") { time in
                    guard total > 0 else { return }
                    onProgress?(min(1, time / total))
                }
            }
            if let audioOutput, let audioInput {
                group.addTask {
                    await pump(audioOutput, into: audioInput, label: "audio", onTime: nil)
                }
            }
        }

        await writer.finishWriting()
        guard writer.status == .completed, reader.status != .failed else {
            try? FileManager.default.removeItem(at: outURL)
            return nil
        }
        return FileManager.default.fileExists(atPath: outURL.path) ? outURL : nil
    }

    /// One track's samples, moved across as fast as the encoder will take them.
    private nonisolated static func pump(
        _ output: AVAssetReaderOutput, into input: AVAssetWriterInput, label: String,
        onTime: (@Sendable (Double) -> Void)?
    ) async {
        let queue = DispatchQueue(label: "com.antonshakirov.minimo.convert.\(label)")
        // reader and writer are not Sendable, and they do not need to be: every
        // touch below happens on this one queue, one sample at a time
        nonisolated(unsafe) let output = output
        nonisolated(unsafe) let input = input
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    guard let sample = output.copyNextSampleBuffer() else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    onTime?(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                    if !input.append(sample) {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    private nonisolated static func softwareTag() -> AVMetadataItem {
        let software = AVMutableMetadataItem()
        software.identifier = .commonIdentifierSoftware
        software.value = "Hop" as NSString
        return software
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
