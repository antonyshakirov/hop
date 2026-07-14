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
    @AppStorage(FileConverter.videoFormatKey) private var videoFormat = "mp4"
    @AppStorage(FileConverter.videoQualityKey) private var videoQuality = "720"
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
        // ⌘V pastes files copied in Finder
        .onPasteCommand(of: [.fileURL]) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await loadFileURL(provider) { urls.append(url) }
                }
                model.converter.addToBatch(urls)
            }
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
            capLine("PDF", "", t(.convCompressOnly))
            capLine(t(.convCanVideo), "MP4 · MOV · M4V", "MP4 / MOV · \(t(.convCompressOnly))")
            capLine(t(.convCanAudio), "MP3 · WAV · FLAC · AAC", "M4A")
            // limitations go right in the table, not only in the help:
            // the user should not discover them by trial and error
            Text(t(.convCantLine))
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
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
        if !batch.unsupported.isEmpty { unsupportedCard(batch.unsupported) }
    }

    private func kindLabel(_ kind: FileConverter.MediaKind) -> String {
        switch kind {
        case .image: return t(.convCanImages)
        case .pdf: return "PDF"
        case .video: return t(.convCanVideo)
        case .audio: return t(.convCanAudio)
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
                        if let res = model.converter.videoResolutions[file.url.path] {
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
                if kind == .image || kind == .pdf {
                    qualityControl(kind)
                }
            }
            HStack {
                if doneCount > 0 {
                    Text("✓ \(doneCount)/\(files.count)")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.accentGreen)
                }
                Spacer()
                if model.converter.activeKind == kind,
                   let fraction = model.converter.fileFraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                        .tint(Theme.accentOrange)
                    Text("\(Int(fraction * 100))%")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.accentOrange)
                        .monospacedDigit()
                }
                if model.converter.activeKind == kind, let progress = model.converter.progress {
                    Text(progress)
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.editing)
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
        .onChange(of: videoQuality) { model.converter.scheduleEstimate(kind) }
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
            EmptyView() // PDF has a single setting — quality, shown in the shared row
        case .video:
            HStack(spacing: 5) {
                rowLabel(t(.convFormatLabel))
                chip("MP4", videoFormat == "mp4") { videoFormat = "mp4" }
                chip("MOV", videoFormat == "mov") { videoFormat = "mov" }
                Spacer()
                chip(t(.convQualityOriginal), videoQuality == "original") { videoQuality = "original" }
                chip(t(.convSqueezeChip), videoQuality == "hevc") { videoQuality = "hevc" }
                    .help(t(.convSqueezeHint))
                chip("1080p", videoQuality == "1080") { videoQuality = "1080" }
                chip("720p", videoQuality == "720") { videoQuality = "720" }
                chip("540p", videoQuality == "540") { videoQuality = "540" }
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
            .hoverHighlight(5)
            Spacer()
            if let result = model.converter.lastResult {
                Text(result)
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accentGreen)
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

    private func chip(_ label: String, _ active: Bool, action: @escaping () -> Void) -> some View {
        SettingChip(label, active: active, action: action)
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
