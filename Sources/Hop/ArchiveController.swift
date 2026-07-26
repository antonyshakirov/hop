import AppKit
import CoreServices
import HopCore

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
    static let helperManifestURL = "https://www.antonshakirov.com/downloads/hop/tools/7zz.json"

    enum Kind: Equatable { case extract, pack }

    enum Failure: Error, Equatable {
        /// The 7-Zip helper could not be fetched or verified.
        case helper
        /// The tool ran but returned an error (a broken or password-protected archive).
        case tool
        /// Nothing usable came out of the archive.
        case empty
        /// macOS refused to write into the destination — the Desktop, Documents
        /// and Downloads folders need explicit consent, and a silent "nothing
        /// appeared" is the worst way to learn that (Anton, 2026-07-25).
        case denied
    }

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
    static let handledContentTypes = [
        "public.zip-archive", "com.rarlab.rar-archive", "org.7-zip.7-zip-archive",
        "public.tar-archive", "org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive",
        "public.bzip2-archive", "org.tukaani.xz-archive",
    ]
    static let defaultHandlerKey = "archiveDefaultHandler"

    /// The app that opens a content type right now, or nil when nothing claims it.
    static func currentHandler(for type: String) -> String? {
        LSCopyDefaultRoleHandlerForContentType(
            type as CFString, .all)?.takeRetainedValue() as String?
    }

    /// **macOS's own app is never overridden** (Anton, 2026-07-26): zip and tar
    /// already open in Archive Utility, and a menu-bar tool has no business
    /// taking that away. Hop offers itself for the types the system leaves to
    /// somebody else — rar and 7z have no native opener at all — and for those
    /// it does replace whatever third-party app got there first.
    static func isAppleHandler(_ bundleID: String?) -> Bool {
        bundleID?.lowercased().hasPrefix("com.apple.") ?? false
    }

    /// Types Hop would claim on a tap: nothing Apple opens, nothing Hop already
    /// holds.
    static var claimableTypes: [String] {
        handledContentTypes.filter { type in
            let current = currentHandler(for: type)
            return !isAppleHandler(current)
                && current?.caseInsensitiveCompare(Bundle.storageIdentifier) != .orderedSame
        }
    }

    /// Hop is the opener for everything it is allowed to open. Read from Launch
    /// Services every time, never from a stored flag: the default can be changed
    /// in Finder at any moment, and a switch that disagrees with the system is
    /// worse than no switch (Anton, 2026-07-26).
    static var isDefaultHandler: Bool {
        let held = handledContentTypes.contains { type in
            currentHandler(for: type)?.caseInsensitiveCompare(Bundle.storageIdentifier) == .orderedSame
        }
        return held && claimableTypes.isEmpty
    }

    /// Claim every type the system does not open itself. There is no "release":
    /// handing a type back means choosing an app FOR the user, and Finder's own
    /// "Open with → Change all" is the honest way out.
    static func claimDefaultHandler() {
        let bundleID = Bundle.storageIdentifier
        for type in claimableTypes {
            LSSetDefaultRoleHandlerForContentType(
                type as CFString, .all, bundleID as CFString)
        }
        UserDefaults.standard.set(true, forKey: defaultHandlerKey)
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
            for archive in items { extract(archive) }
        case .pack:
            pack(items)
        }
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

    private func extract(_ archive: URL) {
        guard let format = ArchiveRules.format(ofFileNamed: archive.lastPathComponent) else { return }
        let folder = destinationFolder(nextTo: archive)
        let job = Job(kind: .extract, name: archive.lastPathComponent, state: .running)
        append(job)
        Task {
            if !format.isNative, !helper.isInstalled {
                update(job.id, .waitingForHelper)
                await helper.install()
                guard helper.isInstalled else {
                    update(job.id, .failed(.helper))
                    return
                }
                update(job.id, .running)
            }
            let helperPath = helper.installedBinaryURL()?.path
            let result = await Task.detached(priority: .userInitiated) {
                Self.runExtract(archive: archive, into: folder, format: format, helper: helperPath)
            }.value
            switch result {
            case .success(let path):
                update(job.id, .done(path))
            case .failure(let failure):
                update(job.id, .failed(failure))
            }
        }
    }

    /// Unpack into a hidden staging folder INSIDE the destination, then lift the
    /// result out. That gives two things at once: an archive of many loose files
    /// never scatters them over the folder (it gets one folder named after the
    /// archive), and a single-item archive does not gain a pointless wrapper.
    /// Staging inside the destination also means the move is instant — same volume.
    private nonisolated static func runExtract(
        archive: URL, into destination: URL, format: ArchiveFormat, helper: String?
    ) -> Result<String, Failure> {
        let manager = FileManager.default
        let staging = destination.appendingPathComponent(".hop-unpack-\(UUID().uuidString)")
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            // The Desktop, Documents and Downloads folders are gated by macOS:
            // without consent every write fails and the result would silently
            // never appear (Anton, 2026-07-25). Say so instead.
            return .failure(isPermissionError(error) ? .denied : .tool)
        }
        defer { try? manager.removeItem(at: staging) }

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

        let produced = (try? manager.contentsOfDirectory(atPath: staging.path))?
            .filter { $0 != ".DS_Store" } ?? []
        guard !produced.isEmpty else { return .failure(.empty) }

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
            return .failure(.tool)
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
                await helper.install()
                guard helper.isInstalled else {
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
