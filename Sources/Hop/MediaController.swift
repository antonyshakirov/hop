import AppKit
import AVFoundation
import Combine
import CoreML
import HopCore
import UniformTypeIdentifiers
import Vision

@MainActor
final class MediaController: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        let video: Bool
        let size: MediaSize
        let duration: Double
        var framesPerSecond = 0.0
        var original: NSImage?
        var resolution: MediaResolution = .double
        var subject = 0
        var subjects: [Int] = []
        var result: NSImage?
        var exported: URL?
        var error: L10nKey?
        var progress = 0.0
        var hasTransparency = false
        var sourceBytes: Int64?
        var outputBytes: Int64?
    }
    private struct Result: @unchecked Sendable {
        var image: CGImage?
        var original: CGImage?
        var subjects: [Int] = []
        var exported: URL?
    }
    @Published var items: [Item] = []
    @Published var selected: UUID?
    @Published var selection: Set<UUID> = []
    var scopedItems: [Item] { items.filter { selection.contains($0.id) } }
    var allFilesSelected: Bool { !items.isEmpty && items.allSatisfy { selection.contains($0.id) } }
    static var removesCompleted: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.mediaRemoveCompleted) as? Bool ?? true
    }
    private var defaultResolution: MediaResolution = .double
    var commonResolutions: [MediaResolution] {
        let eligible = scopedItems.filter { !$0.size.choices.isEmpty }
        return eligible.isEmpty ? [] : MediaResolution.allCases.filter { choice in
            eligible.allSatisfy { $0.size.output(for: choice) != nil }
        }
    }
    func toggleSelection(_ id: UUID) {
        guard !locked, items.contains(where: { $0.id == id }) else { return }
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
    func selectAllFiles() { guard !locked else { return }; selection = Set(items.map(\.id)) }
    func applyResolution(_ choice: MediaResolution) {
        guard !locked, commonResolutions.contains(choice) else { return }
        if allFilesSelected { defaultResolution = choice }
        for item in scopedItems where item.size.output(for: choice) != nil { setResolution(choice, for: item.id) }
    }
    let operation: MediaOperation
    @Published var busy = false
    @Published var importing = false
    @Published var installing = false
    @Published var modelReady = MediaModelStore.ready
    @Published var error: L10nKey?
    @Published var destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    @Published var previewSecond = 0.0 { didSet { invalidateSelected() } }
    private var task: Task<Void, Never>?
    private var worker: Task<Result, Error>?
    private var ingest: Task<Void, Never>?
    private var temporaryInputs: [URL] = []
    @Published private(set) var secondsPerTile = 0.1
    var selectedItem: Item? { items.first { $0.id == selected } }
    var locked: Bool { busy || importing || installing }

    init(operation: MediaOperation = .background) {
        self.operation = operation
    }

    func add(_ urls: [URL]) {
        guard !locked else { return }
        let existing = Set(items.map(\.url))
        let sources = Array(urls.filter { $0.isFileURL && !existing.contains($0) }.prefix(max(0, 200 - items.count)))
        importing = true
        ingest = Task {
            for url in sources {
                if Task.isCancelled { break }
                let video = ((try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .movie)) == true
                do {
                    let size: MediaSize
                    let duration: Double
                    let fps: Double
                    let image: CGImage
                    if video {
                        let info = try await MediaVideoEngine.info(url)
                        size = info.size; duration = info.duration; fps = info.framesPerSecond
                        image = try await MediaVideoEngine.frame(url)
                    } else {
                        image = try await Task.detached { try MediaImageEngine.read(url) }.value
                        size = MediaSize(width: image.width, height: image.height); duration = 0; fps = 0
                    }
                    try Task.checkCancellation()
                    let factor = min(1, 360 / Double(max(size.width, size.height)))
                    let thumbnail = try MediaImageEngine.resize(image, to: MediaSize(width: max(1, Int(Double(size.width) * factor)),
                                                                                   height: max(1, Int(Double(size.height) * factor))))
                    var item = Item(url: url, video: video, size: size, duration: duration,
                                    original: NSImage(cgImage: thumbnail, size: .zero))
                    item.framesPerSecond = fps
                    item.resolution = size.output(for: defaultResolution) != nil ? defaultResolution : (size.choices.first ?? .eightK)
                    item.hasTransparency = !video && MediaImageEngine.hasTransparency(image)
                    item.sourceBytes = Self.fileBytes(url)
                    items.append(item)
                    selection.insert(item.id)
                    if selected == nil { selected = item.id }
                } catch is CancellationError { break }
                catch {
                    let failed = Item(url: url, video: video, size: MediaSize(width: 0, height: 0), duration: 0,
                                      original: nil, error: failureKey(error))
                    items.append(failed)
                    selection.insert(failed.id)
                    if selected == nil { selected = failed.id }
                }
            }
            importing = false
            ingest = nil
        }
    }

    func paste() {
        guard !locked else { return }
        let pasteboard = NSPasteboard.general
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        if !urls.isEmpty { add(urls); return }
        guard let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hop-media-paste-\(UUID().uuidString).png")
        do { try png.write(to: url); temporaryInputs.append(url); add([url]) }
        catch { self.error = .mediaOutputError }
    }

    func clear() {
        guard !locked else { return }
        items = []; selected = nil; selection = []; error = nil
        temporaryInputs.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryInputs = []
    }

    func cancel() { worker?.cancel(); task?.cancel(); ingest?.cancel() }

    func installModel() {
        guard !locked else { return }
        installing = true; error = nil
        task = Task { [self] in
            do { try await MediaModelStore.install(); modelReady = MediaModelStore.ready }
            catch is CancellationError { }
            catch { self.error = .mediaModelError }
            installing = false; task = nil
        }
    }

    func setResolution(_ choice: MediaResolution, for id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), !locked else { return }
        guard items[i].resolution != choice else { return }
        items[i].resolution = choice; items[i].result = nil; items[i].exported = nil; items[i].error = nil
        items[i].outputBytes = nil
        items[i].progress = 0
    }

    func setSubject(_ subject: Int, for id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), !locked else { return }
        items[i].subject = subject; items[i].result = nil; items[i].exported = nil
        items[i].outputBytes = nil
    }

    func invalidate() {
        guard !locked else { return }
        for i in items.indices {
            items[i].result = nil; items[i].exported = nil; items[i].outputBytes = nil; items[i].progress = 0
        }
        error = nil
    }

    func invalidateSelected() {
        guard !locked, let index = items.firstIndex(where: { $0.id == selected }) else { return }
        items[index].result = nil
    }

    func export(quality: MediaExportQuality, background: MediaBackground) {
        run(preview: false, background: background, quality: quality, ids: Set(scopedItems.map(\.id)),
            reexport: true, completeSelection: true, removeCompleted: Self.removesCompleted)
    }

    func run(preview: Bool, background: MediaBackground, quality: MediaExportQuality = .full,
             ids: Set<UUID>? = nil, reexport: Bool = false,
             completeSelection: Bool = false, removeCompleted: Bool = false) {
        guard !locked else { return }
        let jobs = preview ? items.filter { $0.id == selected } : items.filter {
            (ids == nil || ids!.contains($0.id)) && (reexport || $0.exported == nil)
        }
        guard !jobs.isEmpty else { return }
        let operation = operation, folder = destination, previewSecond = previewSecond
        if operation == .upscale, !modelReady { error = .mediaModelError; return }
        busy = true; error = nil
        task = Task { [self] in
            for job in jobs {
                if Task.isCancelled { break }
                guard let index = items.firstIndex(where: { $0.id == job.id }), job.size.width > 0 else { continue }
                let output = operation == .upscale ? job.size.output(for: job.resolution) : nil
                if operation == .upscale, output == nil { items[index].error = .mediaAtMaximum; continue }
                items[index].error = nil; items[index].progress = 0
                let started = Date()
                let worker = Task.detached(priority: .userInitiated) { [weak self] () throws -> Result in
                    let upscaler = operation == .upscale ? try MediaUpscaler() : nil
                    var lastProgress = Date.distantPast
                    let progress: (Double) -> Void = { value in
                        guard value == 1 || Date().timeIntervalSince(lastProgress) >= 0.1 else { return }
                        lastProgress = Date()
                        Task { @MainActor [weak self] in
                            guard let self, self.busy, let i = self.items.firstIndex(where: { $0.id == job.id }) else { return }
                            self.items[i].progress = value
                        }
                    }
                    if job.video, !preview {
                        return Result(exported: try await MediaVideoEngine.export(job.url, to: folder,
                            operation: operation, output: output, subject: job.subject,
                            background: background, upscaler: upscaler, quality: quality, progress: progress))
                    }
                    let original = job.video ? try await MediaVideoEngine.frame(job.url, at: min(previewSecond, max(0, job.duration - 0.05)))
                                             : try MediaImageEngine.read(job.url)
                    var subjects: [Int] = []
                    let result: CGImage
                    if operation == .background {
                        let foreground: CGImage
                        if job.video {
                            let request = VNGeneratePersonSegmentationRequest()
                            request.qualityLevel = .accurate
                            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
                            foreground = try MediaVideoEngine.person(original, request: request, handler: VNSequenceRequestHandler())
                        } else {
                            (foreground, subjects) = try MediaImageEngine.foreground(original, subject: job.subject)
                        }
                        result = try MediaImageEngine.replaceBackground(foreground, with: background)
                    } else {
                        guard let upscaler, let output else { throw MediaFailure.model }
                        result = try upscaler.enhance(original, to: output, progress: progress)
                    }
                    try Task.checkCancellation()
                    let ratio = min(1, 512 / Double(max(result.width, result.height)))
                    let thumbSize = MediaSize(width: max(1, Int(Double(result.width) * ratio)), height: max(1, Int(Double(result.height) * ratio)))
                    let thumbnail = try MediaImageEngine.resize(result, to: thumbSize)
                    let before = try MediaImageEngine.resize(original, to: thumbSize)
                    if preview { return Result(image: thumbnail, original: before, subjects: subjects) }
                    let ext = MediaImageEngine.fileExtension(result, quality: quality)
                    let stage = folder.appendingPathComponent(".hop-media-\(UUID().uuidString).\(ext)")
                    defer { try? FileManager.default.removeItem(at: stage) }
                    try MediaImageEngine.write(result, to: stage, quality: quality)
                    try Task.checkCancellation()
                    let url = folder.appendingPathComponent("\(job.url.deletingPathExtension().lastPathComponent)-\(operation.rawValue)-\(UUID().uuidString.prefix(8)).\(ext)")
                    try FileManager.default.moveItem(at: stage, to: url)
                    return Result(image: thumbnail, subjects: subjects, exported: url)
                }
                self.worker = worker
                do {
                    let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                    guard let i = items.firstIndex(where: { $0.id == job.id }) else { continue }
                    if let image = result.image { items[i].result = NSImage(cgImage: image, size: .zero) }
                    if let image = result.original { items[i].original = NSImage(cgImage: image, size: .zero) }
                    items[i].subjects = result.subjects
                    if let exported = result.exported {
                        items[i].exported = exported
                        items[i].outputBytes = Self.fileBytes(exported)
                    }
                    items[i].progress = 1
                    if completeSelection, result.exported != nil {
                        selection.remove(job.id)
                        if removeCompleted {
                            items.remove(at: i)
                            if selected == job.id { selected = items.first?.id }
                        }
                    }
                    if operation == .upscale, preview {
                        let count = max(1, job.size.inferenceTiles(to: output ?? job.size))
                        secondsPerTile = Date().timeIntervalSince(started) / Double(count)
                    }
                } catch is CancellationError {
                    if let i = items.firstIndex(where: { $0.id == job.id }) { items[i].progress = 0 }
                    break
                }
                catch {
                    if error as? MediaFailure == .model { modelReady = false }
                    if let i = items.firstIndex(where: { $0.id == job.id }) {
                        items[i].progress = 0
                        items[i].error = failureKey(error)
                    }
                }
                self.worker = nil
            }
            worker = nil; busy = false; task = nil
        }
    }

    private static func fileBytes(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private func failureKey(_ error: Error) -> L10nKey {
        switch error as? MediaFailure {
        case .noSubject: return .mediaNoSubject
        case .tooLarge: return .mediaTooLarge
        case .model, .download: return .mediaModelError
        case .output, .codec: return .mediaOutputError
        default: return .convFileFailed
        }
    }
}
