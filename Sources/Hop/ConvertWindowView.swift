import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Standalone converter window: convenient to drag files here from Finder —
/// the status bar popup is no good for that (it collapses on a click outside).
struct ConvertWindowView: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    @AppStorage(FileConverter.formatKey) private var convFormat = "jpeg"
    @AppStorage(FileConverter.scaleKey) private var convScale = 1.0
    @AppStorage(FileConverter.qualityKey) private var convQuality = 55
    @AppStorage(FileConverter.pdfQualityKey) private var convPdfQuality = 55
    @AppStorage(FileConverter.videoFormatKey) private var videoFormat = "original"
    @AppStorage(FileConverter.videoResolutionKey) private var videoResolution = "original"
    @AppStorage(FileConverter.videoCompressKey) private var videoCompress = true
    @AppStorage(FileConverter.videoShapeKey) private var videoShape = "source"
    @AppStorage(FileConverter.videoFitKey) private var videoFit = "fill"
    @AppStorage(FileConverter.videoQualityLevelKey) private var videoQualityLevel = 55
    @AppStorage(FileConverter.docTargetKey) private var docTarget = "pdf"
    @AppStorage(FileConverter.pdfModeKey) private var pdfMode = "compress"
    @State private var targeted = false

    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    private var scrollContent: some View {
        VStack(spacing: 16) {
            dropZone
            if model.converter.batch.isEmpty {
                capabilities
            } else {
                if model.converter.batch.all.contains(where: \.done) {
                    HStack {
                        Spacer()
                        clearDoneButton
                    }
                }
                VStack(spacing: 10) {
                    groupCards
                }
                footer
            }
        }
        .padding(20)
        .background(
            // direct measurement instead of a PreferenceKey: the preference
            // consistently reported 0 through the ScrollView, so the window
            // never resized to fit
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.converterContentHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, height in
                        model.converterContentHeight = height
                    }
            }
        )
    }

    var body: some View {
        // window height is managed by AppDelegate: content up to 70% of the
        // screen, then scrolling; a manual user resize is respected.
        // In snapshots — no ScrollView: ImageRenderer doesn't draw it.
        Group {
            if Snapshot.active {
                scrollContent
            } else {
                ScrollView(showsIndicators: false) {
                    scrollContent
                }
            }
        }
        .frame(width: 540)
        .frame(maxHeight: .infinity)
        .background(Theme.panelBackground)
        // ⌘V ingests everything on the clipboard the converter supports —
        // multiple Finder files at once, a raw screenshot, unsupported items
        // skipped — the same pasteboard path the panel's convert row uses. The
        // reliable ⌘V route is a local keyDown monitor installed with the window
        // (ConverterWindow setup in App.swift): the accessory app has no Edit
        // menu, so onPasteCommand alone never fires, and the window's
        // performKeyEquivalent reaches nothing when the window is not key. This
        // stays as a fallback for any context that does route a paste command
        // (it never double-fires — the monitor consumes ⌘V before it arrives).
        .onPasteCommand(of: [.fileURL, .image]) { _ in
            model.converter.addFromPasteboard()
        }
    }

    private var clearDoneButton: some View {
        Button {
            model.converter.clearDone()
        } label: {
            Text(t(.convClearDone))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Theme.divider, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(t(.convClearDone))
        .hoverHighlight(5)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 20))
                .foregroundStyle(targeted ? Theme.editing : Theme.textTertiary)
            Text(t(.convDrop))
                .font(Theme.mono(11))
                .foregroundStyle(targeted ? Theme.editing : Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    targeted ? Theme.editing : Theme.divider,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await loadFileURL(provider) {
                        urls.append(url)
                    }
                }
                model.converter.addToBatch(urls)
            }
            return true
        }
    }

    private func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Capabilities

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 8) {
            capLine(t(.convCanImages), "JPEG · PNG · HEIC · TIFF · GIF · RAW", imageOutputs)
            capLine("PDF", "PDF", "PDF (\(t(.convCompressOnly))) · MD")
            capLine(t(.convCanVideo), "MP4 · MOV · M4V", "MP4 / MOV (\(t(.convCompressOnly)))")
            capLine(t(.convCanAudio), "MP3 · WAV · FLAC · AAC", "M4A")
            capLine(t(.convCanDocuments), "MD · DOCX · DOC · RTF · TXT", "PDF · MD · DOCX")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 8))
    }

    private var imageOutputs: String {
        var outs = ["JPEG", "PNG", "HEIC"]
        if FileConverter.avifSupported { outs.append("AVIF") }
        return outs.joined(separator: " / ")
    }

    private func capLine(_ label: String, _ input: String, _ output: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(input.isEmpty ? "→ \(output)" : "\(input)  →  \(output)")
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - File groups

    @ViewBuilder private var groupCards: some View {
        let batch = model.converter.batch
        if !batch.images.isEmpty { groupCard(.image, count: batch.images.count) }
        if !batch.pdfs.isEmpty { groupCard(.pdf, count: batch.pdfs.count) }
        if !batch.videos.isEmpty { groupCard(.video, count: batch.videos.count) }
        if !batch.audios.isEmpty { groupCard(.audio, count: batch.audios.count) }
        if !batch.documents.isEmpty { groupCard(.document, count: batch.documents.count) }
        if !batch.unsupported.isEmpty { unsupportedCard(batch.unsupported) }
    }

    private func kindLabel(_ kind: FileConverter.MediaKind) -> String {
        switch kind {
        case .image: return t(.convCanImages)
        case .pdf: return "PDF"
        case .video: return t(.convCanVideo)
        case .audio: return t(.convCanAudio)
        case .document: return t(.convCanDocuments)
        case .unsupported: return t(.convUnsupported)
        }
    }

    private func groupCard(_ kind: FileConverter.MediaKind, count: Int) -> some View {
        let files = model.converter.batch.files(kind)
        let doneCount = files.filter(\.done).count
        let hasPending = doneCount < files.count
        return VStack(alignment: .leading, spacing: 10) {
            // file list instead of a header — what it is is obvious anyway;
            // each file gets a thumbnail and its own "before → after" size
            VStack(alignment: .leading, spacing: 5) {
                ForEach(files.prefix(8)) { file in
                    HStack(spacing: 6) {
                        Image(systemName: file.failed ? "xmark.circle.fill"
                              : file.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 8))
                            .foregroundStyle(file.failed ? Theme.accentRed
                                             : file.done ? Theme.accentGreen : Theme.textTertiary)
                            .help(file.failed ? t(.convFileFailed) : "")
                        FileThumbnail(url: file.url)
                        Text(file.url.lastPathComponent)
                            .font(Theme.mono(10))
                            .foregroundStyle(file.done ? Theme.textTertiary : Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        if let res = model.converter.resolutionTransition(file.url) {
                            Text(res)
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(model.converter.fileEstimates[file.url.path]
                             ?? FileConverter.sizeText(file.bytes))
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if files.count > 8 {
                    Text("+\(files.count - 8)")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            settingsRow(kind)
            HStack(spacing: 8) {
                // the group total only makes sense for multiple files —
                // for a single file it repeats the line above verbatim
                if files.count > 1, let estimate = model.converter.estimates[kind] {
                    Text(estimate)
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                // the quality slider belongs to squeezing; extracting a PDF's
                // text has nothing to tune
                // quality and scale belong to squeezing; extraction has neither
                if kind == .image || (kind == .pdf && (pdfMode == "compress" || pdfMode.isEmpty)) {
                    qualityControl(kind)
                }
            }
            HStack {
                if doneCount > 0 {
                    Text("✓ \(doneCount)/\(files.count)")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.accentGreen)
                } else if hasPending, model.converter.activeKind != kind, kind != .document {
                    // honesty note: the projected sizes are estimates. Documents
                    // show no size forecast at all, so the note would be answering
                    // a question nobody asked.
                    Text(t(.convApproxNote))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if model.converter.activeKind == kind, let progress = model.converter.progress {
                    // conversion status: a whole-batch bar (files done + the
                    // current video's own fraction) and "converting… i/n"
                    let fraction = model.converter.batchFraction ?? 0
                    // Green the moment the work is done, orange while it runs —
                    // one colour for the bar, the percentage and the label.
                    let tint = fraction >= 1 ? Theme.accentGreen : Theme.accentOrange
                    // A bar drawn here rather than a ProgressView: AppKit's own
                    // animates on its own schedule, and with values arriving
                    // several times a second it was still a fifth of the way
                    // along when the percentage beside it read 100 (Anton,
                    // 2026-08-04). This one is exactly as long as the number says.
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.divider)
                            .frame(width: 90, height: 4)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(2, 90 * min(max(fraction, 0), 1)), height: 4)
                    }
                    // No animation: reports already arrive ten times a second,
                    // which is smooth enough, and an animated subtree made the
                    // fill lag its own colour — the percentage went green while
                    // the bar was still orange (Anton, 2026-08-04).
                    Text("\(Int(fraction * 100))%")
                        .font(Theme.mono(10))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                    Text("\(t(.convConverting)) \(progress)")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(tint)
                } else if hasPending {
                    Button {
                        model.converter.convert(kind)
                    } label: {
                        Text(t(.convConvert))
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.playFg)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.playBg, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(t(.convConvert))
                    .hoverDim()
                    .disabled(model.converter.busy)
                    .opacity(model.converter.busy ? 0.4 : 1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { model.converter.scheduleEstimate(kind) }
        .onChange(of: convQuality) { model.converter.scheduleEstimate(kind) }
        .onChange(of: convPdfQuality) { model.converter.scheduleEstimate(kind) }
        .onChange(of: convScale) { model.converter.scheduleEstimate(kind) }
        .onChange(of: convFormat) { model.converter.scheduleEstimate(kind) }
        .onChange(of: videoFormat) { model.converter.scheduleEstimate(kind) }
        .onChange(of: videoResolution) { model.converter.scheduleEstimate(kind) }
        .onChange(of: videoCompress) { model.converter.scheduleEstimate(kind) }
        .onChange(of: videoShape) { model.converter.scheduleEstimate(kind) }
        .onChange(of: videoFit) { model.converter.scheduleEstimate(kind) }
        .onChange(of: videoQualityLevel) { model.converter.scheduleEstimate(kind) }
    }

    @ViewBuilder private func settingsRow(_ kind: FileConverter.MediaKind) -> some View {
        switch kind {
        case .image:
            HStack(spacing: 5) {
                rowLabel(t(.convFormatLabel))
                chip("JPEG", convFormat == "jpeg") { convFormat = "jpeg" }
                chip("PNG", convFormat == "png") { convFormat = "png" }
                chip("HEIC", convFormat == "heic") { convFormat = "heic" }
                if FileConverter.avifSupported {
                    chip("AVIF", convFormat == "avif") { convFormat = "avif" }
                }
                Spacer()
            }
            HStack(spacing: 5) {
                rowLabel(t(.convScaleLabel))
                scaleChips
                Spacer()
            }
        case .pdf:
            // two jobs, not one: squeeze the file (the quality row below) or pull
            // its text out as markdown
            HStack(spacing: 5) {
                rowLabel(t(.convModeLabel))
                chip(t(.convModeCompress), pdfMode == "compress" || pdfMode.isEmpty) {
                    pdfMode = "compress"
                }
                chip("md", pdfMode == "markdown") { pdfMode = "markdown" }
                chip("docx", pdfMode == "docx") { pdfMode = "docx" }
                Spacer()
            }
        case .document:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    rowLabel(t(.convFormatLabel))
                    ForEach(DocumentConversion.Target.allCases) { target in
                        chip(target.label, docTarget == target.rawValue) {
                            docTarget = target.rawValue
                        }
                    }
                    Spacer()
                }
                // the honest caveat, in the UI rather than only in the docs
                Text(t(.convDocNote))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .video:
            // three independent settings (Anton, 2026-07-15): container format,
            // target resolution (only options below the source) and a separate
            // compress toggle (HEVC instead of H.264)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    rowLabel(t(.convFormatLabel))
                    // "original" keeps the container the file arrived in: mp4 in,
                    // mp4 out. Changing it does nothing for size and is only
                    // worth doing on purpose (Anton, 2026-08-04).
                    chip(t(.convQualityOriginal), videoFormat == "original") { videoFormat = "original" }
                    chip("MP4", videoFormat == "mp4") { videoFormat = "mp4" }
                    chip("MOV", videoFormat == "mov") { videoFormat = "mov" }
                    Spacer()
                }
                HStack(spacing: 5) {
                    rowLabel(t(.convResolutionLabel))
                    chip(t(.convQualityOriginal), videoResolution == "original") { videoResolution = "original" }
                    // The row never changes shape: every resolution is always
                    // here, and the ones the source has no pixels for are dimmed
                    // rather than removed. Labels go by the SHORT side, scaling
                    // keeps the aspect ratio, and nothing is ever upscaled.
                    let sourceSide = model.converter.videoMaxShortSide
                    ForEach([("4K", 2160), ("1080p", 1080), ("720p", 720), ("540p", 540)], id: \.1) { label, side in
                        let available = sourceSide == 0 || side <= sourceSide
                        chip(label, videoResolution == String(side), enabled: available) {
                            videoResolution = String(side)
                        }
                    }
                    Spacer()
                }
                // The SHAPE, which is what a platform actually asks for: a reel
                // is 9:16 whatever its resolution. Ratios are written as ratios
                // — every platform states them that way, and a name would go
                // stale the moment one of them renames a format.
                HStack(spacing: 5) {
                    rowLabel(t(.convFrameLabel))
                    chip(t(.convQualityOriginal), videoShape == "source") { videoShape = "source" }
                    chip("9:16", videoShape == "vertical") { videoShape = "vertical" }
                    chip("4:5", videoShape == "portrait") { videoShape = "portrait" }
                    chip("1:1", videoShape == "square") { videoShape = "square" }
                    chip("16:9", videoShape == "landscape") { videoShape = "landscape" }
                    Spacer()
                }
                // What happens to a picture of another shape — asked only when
                // there is a reshaping to do
                if videoShape != "source" {
                    HStack(spacing: 5) {
                        rowLabel(t(.convFitLabel))
                        chip(t(.convFitCrop), videoFit == "fill") { videoFit = "fill" }
                        chip(t(.convFitBars), videoFit == "pad") { videoFit = "pad" }
                        chip(t(.convFitBlur), videoFit == "blur") { videoFit = "blur" }
                        Spacer()
                    }
                }
                // resolution is our own composition, so HEVC works at ANY size
                HStack(spacing: 8) {
                    rowLabel(t(.convCompressLabel))
                    Theme.MiniSwitch(isOn: $videoCompress)
                    // how hard, not just whether: the encoder is given a bitrate
                    // rather than a preset, so this dial has something to turn
                    if videoCompress {
                        MiniSlider(value: $videoQualityLevel, range: 1...100, width: 96)
                    }
                    Spacer()
                }
                .help(t(.convSqueezeHint))
            }
        case .audio:
            HStack(spacing: 5) {
                rowLabel(t(.convFormatLabel))
                // exactly one format: macOS has no MP3/FLAC encoders and we
                // do not bundle ffmpeg — show the choice explicitly, not as emptiness
                chip("M4A (AAC)", true) {}
                    .help(t(.convAudioOnlyHint))
                Spacer()
            }
        case .unsupported:
            EmptyView()
        }
    }

    private func unsupportedCard(_ files: [FileConverter.BatchFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(t(.convUnsupported)) · \(files.count)")
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.accentOrange)
            ForEach(files.prefix(6)) { file in
                Text(file.url.lastPathComponent)
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if files.count > 6 {
                Text("+\(files.count - 6)")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            Button {
                model.converter.clearBatch()
            } label: {
                Text(t(.convClear))
                    .font(Theme.mono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Theme.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t(.convClear))
            .hoverHighlight(5)
            Spacer()
            if let result = model.converter.lastResult {
                Text(result)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accentGreen)
            }
            // "where did it go" — answered by Finder, with the file selected
            if let output = model.converter.lastOutput {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(output.deletingLastPathComponent().lastPathComponent)
                            .font(Theme.mono(10))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Theme.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t(.convReveal))
                .hoverHighlight(5)
            }
        }
    }

    // MARK: - Small details

    private var scaleChips: some View {
        HStack(spacing: 5) {
            chip("0.25×", convScale == 0.25) { convScale = 0.25 }
            chip("0.5×", convScale == 0.5) { convScale = 0.5 }
            chip("0.75×", convScale == 0.75) { convScale = 0.75 }
            chip("1×", convScale == 1.0) { convScale = 1.0 }
        }
    }

    /// PDF gets its own quality slider: the shared one also moved images along with it.
    private func qualityControl(_ kind: FileConverter.MediaKind) -> some View {
        HStack(spacing: 6) {
            rowLabel(t(.convQualityLabel))
            MiniSlider(value: kind == .pdf ? $convPdfQuality : $convQuality,
                       range: 1...100, width: 96)
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.textTertiary)
    }


    private func chip(
        _ label: String, _ active: Bool, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        SettingChip(label, active: active, enabled: enabled, action: action)
    }
}

/// File thumbnail in a converter row: QuickLook preview with a cache.
/// In snapshots (.task does not run in ImageRenderer) the placeholder remains — not a bug.
struct FileThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.divider, lineWidth: 1))
        .task(id: url) {
            let key = url.path as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                return
            }
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 48, height: 48),
                scale: 2, representationTypes: .thumbnail
            )
            guard let rep = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request) else { return }
            let thumb = rep.nsImage
            Self.cache.setObject(thumb, forKey: key)
            image = thumb
        }
    }
}
