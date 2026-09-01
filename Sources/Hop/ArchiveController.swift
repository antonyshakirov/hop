import AppKit
import HopCore
import UniformTypeIdentifiers

/// Drag & drop archiving: drop an archive and it is unpacked NEXT TO the
/// original; drop files or folders and they are packed there instead. No
/// windows, no wizard — the drop itself is the whole interface.
///
/// zip, tar and gzip are handled by tools every Mac already has. rar and 7z
/// need the 7-Zip helper, which is fetched once, on demand, and only after its
/// signature checks out (`ToolInstaller`). Hop never CREATES rar: the format is
/// proprietary and no free packer may write it.
@MainActor
final class ArchiveController: ObservableObject {
    static let packFormatKey = "archivePackFormat"
    static let destinationKey = "archiveDestination"
    static let destinationPathKey = "archiveDestinationPath"
    static let helperManifestURL = "https://hop.tools/downloads/hop/tools/7zz.json"

    enum Kind: Equatable { case extract, pack }

    typealias Failure = ArchiveFailureKind

    /// Where results are written. The Desktop is the default: an unpacked folder
    /// has to be somewhere the user is already looking (Anton, 2026-07-25).
    enum Destination: String, CaseIterable, Identifiable, Sendable {
        case desktop, alongside, custom
        public var id: String { rawValue }
    }

    enum JobState: Equatable {
        case waitingForHelper
        case running
        /// Path of what was produced — the row reveals it in Finder.
        case done(String)
        case failed(Failure)
    }

    struct Job: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        /// What the row shows: the archive being unpacked, or the archive being made.
        var name: String
        var state: JobState
    }

    @Published private(set) var jobs: [Job] = []
    /// Files waiting for the user to press the button. Adding something never
    /// starts work on its own: a drop is "here are the files", not "go" (Anton,
    /// 2026-07-25).
    @Published private(set) var pending: [URL] = []
    /// The 7-Zip helper, fetched only when a rar/7z actually turns up.
    let helper = ToolInstaller(manifestURL: ArchiveController.helperManifestURL,
                               folderName: "tools",
                               binaryName: "7zz")

    /// How many finished rows stay on screen; older ones fall off so the module
    /// cannot grow without bound during a long session.
    private static let maxJobs = 4
    /// Current-launch staging directories are never swept as orphans, so several
    /// archives may extract concurrently into the same destination.
    private let extractionSessionID = UUID()
    /// Choosing a collision-free name and moving the staged result must be one
    /// operation. Separate extraction tasks may finish at the same instant.
    private nonisolated static let resultMoveLock = NSLock()
    /// Several Finder-opened rar/7z files can arrive in one event. They all await
    /// one helper installation instead of racing several downloads and writes.
    private var helperInstallTask: Task<Bool, Never>?

    init() {
        let sessionID = extractionSessionID
        var folders = [Self.desktopFolder]
        let customPath = UserDefaults.standard.string(forKey: Self.destinationPathKey) ?? ""
        if !customPath.isEmpty {
            folders.append(URL(fileURLWithPath: customPath))
        }
        Task.detached(priority: .utility) {
            for folder in Set(folders) {
                try? ArchiveStaging.removeOrphans(
                    in: folder,
                    preserving: sessionID)
            }
        }
    }

    var packFormat: PackFormat {
        get { PackFormat(rawValue: UserDefaults.standard.string(forKey: Self.packFormatKey) ?? "") ?? .zip }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.packFormatKey) }
    }

    var destination: Destination {
        get { Destination(rawValue: UserDefaults.standard.string(forKey: Self.destinationKey) ?? "") ?? .desktop }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.destinationKey) }
    }

    /// The folder behind `.custom`, empty until one is chosen.
    var customDestinationPath: String {
        get { UserDefaults.standard.string(forKey: Self.destinationPathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.destinationPathKey) }
    }

    /// What pressing the button would do with what is waiting: a queue of
    /// NOTHING BUT archives unpacks, anything else packs into one archive.
    /// A mixed set packs — collecting several things together reads as
    /// "make this one archive".
    var plannedKind: Kind? {
        guard !pending.isEmpty else { return nil }
        let archives = pending.filter {
            !isDirectory($0) && ArchiveRules.format(ofFileNamed: $0.lastPathComponent) != nil
        }
        return archives.count == pending.count ? .extract : .pack
    }

    /// True for a queued file that will be unpacked; the pack format has nothing
    /// to say about it, so the row shows no format (Anton, 2026-07-25).
    func willUnpack(_ url: URL) -> Bool {
        !isDirectory(url) && ArchiveRules.format(ofFileNamed: url.lastPathComponent) != nil
    }

    /// Content types Hop offers to open. Claiming them makes a double-clicked
    /// archive unpack through Hop even when the module is hidden from the panel
    /// (Anton, 2026-07-25) — the same deal the torrent module offers.
    static let handledContentTypes = ArchiveHandlerRules.handledContentTypes

    /// The app that opens a content type right now, or nil when nothing claims it.
    static func currentHandler(for type: String) -> String? {
        let contentType = UTType(importedAs: type)
        return NSWorkspace.shared.urlForApplication(toOpen: contentType)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    /// **macOS's own app is never overridden** (Anton, 2026-07-26): zip and tar
    /// already open in Archive Utility, and a menu-bar tool has no business
    /// taking that away. Hop offers itself for the types the system leaves to
    /// somebody else. Today the only such type Hop offers to claim is rar.
    static func isAppleHandler(_ bundleID: String?) -> Bool {
        ArchiveHandlerRules.isAppleHandler(bundleID)
    }

    /// The ONE type Hop offers to take over: rar, which no Apple app opens on the
    /// macOS versions Hop supports. zip, tar, gz, bz2, xz and even 7z are opened
    /// by Archive Utility, and taking those away from a system app nobody asked
    /// to replace is exactly the kind of squatting a menu-bar tool should not do
    /// (Anton, 2026-07-26).
    static let claimableContentTypes = ArchiveHandlerRules.claimableContentTypes

    /// What a tap would actually change: the claimable types that Apple does not
    /// already open and Hop does not already hold. If a future macOS learns rar,
    /// this list goes empty on its own and the card stops offering anything.
    static var claimableTypes: [String] {
        claimableContentTypes.filter { type in
            ArchiveHandlerRules.shouldClaim(
                currentHandler: currentHandler(for: type),
                hopBundleID: Bundle.storageIdentifier)
        }
    }

    /// Whether Hop holds anything it was never meant to hold — the state left by
    /// versions that claimed every archive type. Drives the "give them back" row.
    static var holdsSystemTypes: Bool {
        handledContentTypes.contains { type in
            ArchiveHandlerRules.holdsUnexpectedType(
                contentType: type,
                currentHandler: currentHandler(for: type),
                hopBundleID: Bundle.storageIdentifier)
        }
    }

    /// Hand only the non-rar types an earlier Hop version still owns back to
    /// Archive Utility. Third-party choices and the allowed rar association are
    /// left untouched.
    static func releaseDefaultHandlers() async {
        guard !Bundle.isDevBuild else { return }
        guard let archiveUtility = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.archiveutility")
        else { return }
        let ours = Bundle.storageIdentifier
        let currentHandlers = Dictionary(
            uniqueKeysWithValues: ArchiveHandlerRules.archiveUtilityContentTypes
                .compactMap { type in currentHandler(for: type).map { (type, $0) } })
        for type in ArchiveHandlerRules.contentTypesToRestore(
            currentHandlers: currentHandlers,
            hopBundleID: ours) {
            if currentHandler(for: type)?
                .caseInsensitiveCompare(ours) == .orderedSame {
                await setDefaultApplication(archiveUtility, for: type)
            }
        }
    }

    /// Hop opens everything it is allowed to open. Read from Launch Services
    /// every time, never from a stored flag: the default can be changed in Finder
    /// at any moment, and a control that disagrees with the system is worse than
    /// no control (Anton, 2026-07-26).
    static var isDefaultHandler: Bool {
        let held = claimableContentTypes.contains { type in
            currentHandler(for: type)?.caseInsensitiveCompare(Bundle.storageIdentifier) == .orderedSame
        }
        return held && claimableTypes.isEmpty
    }

    /// Claim every type the system does not open itself. There is no "release":
    /// handing a type back means choosing an app FOR the user, and Finder's own
    /// "Open with → Change all" is the honest way out.
    static func claimDefaultHandler() async {
        guard !Bundle.isDevBuild else { return }
        let application = Bundle.main.bundleURL
        for type in claimableTypes {
            await setDefaultApplication(application, for: type)
        }
    }

    private static func setDefaultApplication(_ application: URL, for type: String) async {
        let contentType = UTType(importedAs: type)
        await withCheckedContinuation { continuation in
            NSWorkspace.shared.setDefaultApplication(
                at: application,
                toOpen: contentType
            ) { _ in
                continuation.resume()
            }
        }
    }

    /// The one entry point: everything dropped on the module — or pasted into its
    /// window — lands in the queue. Nothing runs until `start()`.
    func handleDrop(_ urls: [URL]) {
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return }
        let known = Set(pending.map(\.path))
        // several files at once, in the order they arrived, each counted once
        for file in files where !known.contains(file.path) {
            pending.append(file.standardizedFileURL)
        }
    }

    /// ⌘V in the archive window: the same queue, filled from the pasteboard.
    /// Copying files in Finder puts their URLs on the pasteboard, so a paste of
    /// several files queues all of them (Anton, 2026-07-25).
    func addFromPasteboard() {
        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        handleDrop(urls)
    }

    func removePending(_ url: URL) {
        pending.removeAll { $0.path == url.path }
    }

    func clearPending() {
        pending.removeAll()
    }

    /// Run what is queued: every archive is unpacked, or everything is packed
    /// into one archive. The queue empties — the jobs list takes over from here.
    func start() {
        guard let kind = plannedKind else { return }
        let items = pending
        pending.removeAll()
        switch kind {
        case .extract:
            for archive in items {
                extract(archive, into: destinationFolder(nextTo: archive))
            }
        case .pack:
            pack(items)
        }
    }

    /// A Finder double-click is a complete command, not an addition to the
    /// interactive queue. It extracts only this archive, always beside the
    /// source, and reports progress to the separate transient Finder window.
    func openFromFinder(
        _ archive: URL,
        onProgress: @escaping (FinderArchiveProgressEvent) -> Void
    ) {
        extract(
            archive,
            into: ArchiveRules.finderDestination(for: archive),
            invocation: .finder,
            onProgress: onProgress)
    }

    /// Where a result is written. `.alongside` keeps the old behaviour (next to
    /// the original); the default is the Desktop, and a custom folder that has
    /// gone missing falls back to it rather than failing.
    private func destinationFolder(nextTo original: URL) -> URL {
        switch destination {
        case .alongside:
            return original.deletingLastPathComponent()
        case .custom:
            let path = customDestinationPath
            if !path.isEmpty, isDirectory(URL(fileURLWithPath: path)) {
                return URL(fileURLWithPath: path)
            }
            return Self.desktopFolder
        case .desktop:
            return Self.desktopFolder
        }
    }

    static let desktopFolder: URL = FileManager.default
        .urls(for: .desktopDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

    /// Staged rows for design snapshots (`--archive`); jobs are otherwise
    /// in-memory only, so a render has nothing to show without this.
    func loadDemo(_ demo: [Job], pending: [URL] = []) {
        guard Snapshot.active else { return }
        jobs = demo
        self.pending = pending
    }

    func clear() {
        jobs.removeAll { if case .running = $0.state { return false } else { return true } }
    }

    // MARK: - Extract

    private func extract(
        _ archive: URL,
        into folder: URL,
        invocation: ArchiveInvocation = .manual,
        onProgress: ((FinderArchiveProgressEvent) -> Void)? = nil
    ) {
        guard let format = ArchiveRules.format(ofFileNamed: archive.lastPathComponent) else { return }
        let job = Job(kind: .extract, name: archive.lastPathComponent, state: .running)
        let recordsManualJob = invocation.recordsManualJob
        if recordsManualJob {
            append(job)
        }
        Task {
            if !format.isNative, !helper.isInstalled {
                if recordsManualJob {
                    update(job.id, .waitingForHelper)
                }
                onProgress?(.waitingForHelper)
                guard await ensureHelperInstalled() else {
                    if recordsManualJob {
                        update(job.id, .failed(.helper))
                    }
                    onProgress?(.failed(.helper))
                    return
                }
                if recordsManualJob {
                    update(job.id, .running)
                }
                onProgress?(.extracting)
            }
            let helperPath = helper.installedBinaryURL()?.path
            let sessionID = extractionSessionID
            let result = await Task.detached(priority: .userInitiated) {
                Self.runExtract(
                    archive: archive,
                    into: folder,
                    format: format,
                    helper: helperPath,
                    sessionID: sessionID)
            }.value
            switch result {
            case .success(let path):
                if recordsManualJob {
                    update(job.id, .done(path))
                }
                onProgress?(.succeeded)
            case .failure(let failure):
                if recordsManualJob {
                    update(job.id, .failed(failure))
                }
                onProgress?(.failed(failure))
            }
        }
    }

    private func ensureHelperInstalled() async -> Bool {
        if helper.isInstalled { return true }
        if let helperInstallTask {
            return await helperInstallTask.value
        }
        let helper = helper
        let task = Task { @MainActor in
            await helper.install()
            return helper.isInstalled
        }
        helperInstallTask = task
        let installed = await task.value
        helperInstallTask = nil
        return installed
    }

    /// Unpack into a hidden staging folder INSIDE the destination, then lift the
    /// result out. That gives two things at once: an archive of many loose files
    /// never scatters them over the folder (it gets one folder named after the
    /// archive), and a single-item archive does not gain a pointless wrapper.
    /// Staging inside the destination also means the move is instant — same volume.
    private nonisolated static func runExtract(
        archive: URL,
        into destination: URL,
        format: ArchiveFormat,
        helper: String?,
        sessionID: UUID
    ) -> Result<String, Failure> {
        let manager = FileManager.default
        do {
            return try ArchiveStaging.withDirectory(
                in: destination,
                sessionID: sessionID,
                fileManager: manager
            ) { staging in
                runExtract(
                    archive: archive,
                    from: staging,
                    into: destination,
                    format: format,
                    helper: helper,
                    fileManager: manager)
            }
        } catch {
            // The Desktop, Documents and Downloads folders are gated by macOS:
            // without consent every write fails and the result would silently
            // never appear (Anton, 2026-07-25). Say so instead.
            return .failure(isPermissionError(error) ? .denied : .tool)
        }
    }

    private nonisolated static func runExtract(
        archive: URL,
        from staging: URL,
        into destination: URL,
        format: ArchiveFormat,
        helper: String?,
        fileManager manager: FileManager
    ) -> Result<String, Failure> {
        let ok: Bool
        switch format {
        case .zip:
            // ditto restores macOS metadata a plain unzip would drop
            ok = run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        case .tar, .tarGz, .tarBz2, .tarXz:
            // bsdtar detects the compression itself and strips absolute paths
            ok = run("/usr/bin/tar", ["-xf", archive.path, "-C", staging.path])
        case .gzip:
            // a bare .gz holds ONE file and no name for it: reuse the archive's
            // own stem, which is what gunzip would have produced in place
            let name = ArchiveRules.baseName(ofArchive: archive.lastPathComponent)
            ok = run("/usr/bin/gunzip", ["-c", archive.path],
                     writingTo: staging.appendingPathComponent(name))
        case .sevenZip, .rar:
            guard let helper else { return .failure(.helper) }
            ok = run(helper, ["x", "-y", "-bd", "-o\(staging.path)", archive.path])
        }
        guard ok else { return .failure(.tool) }

        let produced: [String]
        do {
            produced = try manager.contentsOfDirectory(atPath: staging.path)
                .filter { $0 != ".DS_Store" }
        } catch {
            return .failure(isPermissionError(error) ? .denied : .tool)
        }
        guard !produced.isEmpty else { return .failure(.empty) }

        Self.resultMoveLock.lock()
        defer { Self.resultMoveLock.unlock() }

        let taken = Set((try? manager.contentsOfDirectory(atPath: destination.path)) ?? [])
        let finalName: String
        if produced.count == 1 {
            // one top-level item: keep ITS name, only resolving a collision
            let item = produced[0]
            let stem = (item as NSString).deletingPathExtension
            let ext = (item as NSString).pathExtension
            finalName = ArchiveRules.uniqueName(
                base: stem.isEmpty ? item : stem, extension: ext, taken: taken)
        } else {
            finalName = ArchiveRules.uniqueName(
                base: ArchiveRules.baseName(ofArchive: archive.lastPathComponent),
                extension: "", taken: taken)
        }
        let target = destination.appendingPathComponent(finalName)
        let source = produced.count == 1
            ? staging.appendingPathComponent(produced[0])
            : staging
        do {
            try manager.moveItem(at: source, to: target)
        } catch {
            return .failure(isPermissionError(error) ? .denied : .tool)
        }
        return .success(target.path)
    }

    // MARK: - Pack

    private func pack(_ items: [URL]) {
        let paths = items.map(\.path)
        // The working directory stays the items' own parent — that is what keeps
        // "shoot/one.raw" inside the archive instead of this Mac's full path —
        // while the archive ITSELF is written wherever the user chose.
        let parent = ArchiveRules.commonParent(of: paths)
            ?? items[0].deletingLastPathComponent().path
        let folder = destinationFolder(nextTo: items[0])
        let format = packFormat
        let base = ArchiveRules.packBaseName(for: paths, commonParent: parent)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = ArchiveRules.uniqueName(base: base, extension: format.fileExtension, taken: taken)

        let job = Job(kind: .pack, name: name, state: .running)
        append(job)
        Task {
            if !format.isNative, !helper.isInstalled {
                update(job.id, .waitingForHelper)
                guard await ensureHelperInstalled() else {
                    update(job.id, .failed(.helper))
                    return
                }
                update(job.id, .running)
            }
            let helperPath = helper.installedBinaryURL()?.path
            let names = items.map(\.lastPathComponent)
            let output = folder.appendingPathComponent(name).path
            let result = await Task.detached(priority: .userInitiated) {
                Self.runPack(names: names, in: parent, to: output, format: format, helper: helperPath)
            }.value
            switch result {
            case .success(let path):
                update(job.id, .done(path))
            case .failure(let failure):
                update(job.id, .failed(failure))
            }
        }
    }

    /// Every packer runs WITH THE PARENT AS ITS WORKING DIRECTORY and is handed
    /// bare item names, so the archive holds "shoot/one.raw" rather than the
    /// whole "/Users/…" path of this particular Mac.
    private nonisolated static func runPack(
        names: [String], in parent: String, to destination: String,
        format: PackFormat, helper: String?
    ) -> Result<String, Failure> {
        let folder = (destination as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: folder) else {
            return .failure(.denied)
        }
        let ok: Bool
        switch format {
        case .zip:
            // -X leaves out the resource-fork junk ("__MACOSX") that makes a Hop
            // archive look messy when opened on Windows or Linux
            ok = run("/usr/bin/zip", ["-r", "-q", "-X", destination] + names, cwd: parent)
        case .tarGz:
            ok = run("/usr/bin/tar", ["--no-mac-metadata", "-czf", destination] + names, cwd: parent)
        case .sevenZip:
            guard let helper else { return .failure(.helper) }
            ok = run(helper, ["a", "-y", "-bd", destination] + names, cwd: parent)
        }
        guard ok, FileManager.default.fileExists(atPath: destination) else {
            // a half-written archive is worse than none
            try? FileManager.default.removeItem(atPath: destination)
            return .failure(.tool)
        }
        return .success(destination)
    }

    // MARK: - Process plumbing

    @discardableResult
    private nonisolated static func run(
        _ tool: String, _ arguments: [String], cwd: String? = nil, writingTo output: URL? = nil
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        var handle: FileHandle?
        if let output {
            guard FileManager.default.createFile(atPath: output.path, contents: nil),
                  let file = try? FileHandle(forWritingTo: output) else { return false }
            handle = file
            process.standardOutput = file
        }
        // the tools are chatty on failure; their output would only pollute the log
        process.standardError = FileHandle.nullDevice
        defer { try? handle?.close() }
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private nonisolated func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// A write refused by the file system or by macOS's own folder gate. Both
    /// arrive as Cocoa errors; the POSIX code is what tells them apart from a
    /// full disk or a missing folder.
    private nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EPERM) || underlying.code == Int(EACCES) { return true }
        return false
    }

    private func append(_ job: Job) {
        jobs.insert(job, at: 0)
        // keep the running ones no matter what; only settled rows fall off
        if jobs.count > Self.maxJobs {
            var trimmed = jobs
            while trimmed.count > Self.maxJobs,
                  let index = trimmed.lastIndex(where: { $0.state != .running }) {
                trimmed.remove(at: index)
            }
            jobs = trimmed
        }
    }

    private func update(_ id: UUID, _ state: JobState) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
    }
}
