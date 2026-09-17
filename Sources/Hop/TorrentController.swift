import Combine
import Foundation
import HopCore
import AppKit
import Network
import OSLog

@MainActor
final class TorrentController: ObservableObject {
    let installer = TorrentEngineInstaller()
    private let process = TorrentEngineProcess()
    private var client: TorrentEngineClient?
    private var pollTask: Task<Void, Never>?
    private var stallWatch = TorrentStallWatch()
    private var pathMonitor: NWPathMonitor?
    private var recoveryPending = false
    private var lastRecoveryAttempt: TimeInterval = 0
    /// Starts in a row that brought no engine up; spaces the next one out.
    private var recoveryFailures = 0
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "Torrents")
    private var remapPending = false
    private var sessionStarted = false
    /// False once the engine was stopped on purpose; nothing but a new add or restore may start it.
    private var engineWanted = false
    /// Stops while the Mac sleeps, so a night asleep never reads as a stall.
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @Published private(set) var torrents: [TorrentItem] = []
    private var removals = TorrentRemovals()
    private var addsInFlight = 0

    /// Which torrents are unfolded into their per-file list. Lives here, NOT in
    /// TorrentView's @State, because the panel tags TorrentView with
    /// `.id(themeVersion)` and bumps themeVersion on every app activation — the
    /// keyboard-transparent panel deactivates/reactivates the app on each click,
    /// so @State would reset and the freshly-expanded list would collapse at once.
    @Published var expandedIds: Set<String> = []
    func toggleExpanded(_ id: String) {
        if expandedIds.contains(id) { expandedIds.remove(id) } else { expandedIds.insert(id) }
    }

    /// The installer is a nested ObservableObject. Forward its changes so views
    /// observing this controller react to the download/verify/installed states —
    /// otherwise "enable torrents" runs but the UI never updates.
    private var forwarders: [AnyCancellable] = []
    init() {
        removals = (try? Data(contentsOf: removalsFile))
            .flatMap { try? JSONDecoder().decode(TorrentRemovals.self, from: $0) } ?? TorrentRemovals()
        forwarders.append(installer.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
    }

    /// One torrent mid-download for the onboarding picture: an empty add plate
    /// says nothing about what the module does. SPEC: docs/spec.md —
    /// "Onboarding", the module preview.
    func loadDemo() {
        let total: Int64 = 5_400_000_000
        let file = TorrentFile(index: 0, name: "ubuntu-24.04-desktop-amd64.iso",
                               lengthBytes: total, selected: true)
        torrents = [
            TorrentItem(id: "demo-1", infoHash: "demo", name: "ubuntu-24.04-desktop-amd64.iso",
                        files: [file], outputFolder: "/Users/preview/Downloads",
                        stats: TorrentStats(state: .live, progressBytes: 3_726_000_000,
                                            totalBytes: total, uploadedBytes: 412_000_000,
                                            downloadBps: 11_400_000, uploadBps: 1_260_000,
                                            peersLive: 24, peersSeen: 61, etaSeconds: 147,
                                            finished: false, fileProgressBytes: [3_726_000_000])),
        ]
    }

    struct TorrentItem: Identifiable, Equatable {
        var id: String            // var: re-mapped to the new session id if the engine is restarted
        let infoHash: String      // stable identity across engine restarts
        var name: String
        var files: [TorrentFile]
        var outputFolder: String
        var stats: TorrentStats?
        var notifiedDone: Bool = false
        var pausedByPolicy: Bool = false
        var seedPolicyOverridden: Bool = false
        /// Optimistic pause state: set the instant the user taps pause/play so the
        /// button flips without the ~1.5s poll lag. Cleared back to nil once a poll
        /// confirms the engine reached the same state (`nil` = trust engine truth).
        var optimisticPaused: Bool?
        /// Added from a magnet link (vs a .torrent file) — drives the remove label
        /// ("delete magnet" vs "delete torrent").
        var fromMagnet: Bool = false
        /// The payload was deleted from disk (via Finder, not via Hop) while the
        /// torrent was still downloading. Set by the poll's deletion probe, which
        /// also pauses the torrent so the engine stops writing into nothing. The
        /// row shows a "files removed" state; resume re-downloads, clearing this.
        /// SPEC: docs/spec.md "A seeding torrent whose file is gone is paused" — persisted.
        var filesMissing: Bool = false
    }

    /// What the user handed us to add. A magnet/HTTP-URL travels as a string;
    /// a dropped `.torrent` file travels as its raw bytes. Both become the POST
    /// body verbatim — rqbit sniffs the content, so bytes must not be re-encoded.
    enum AddSource: Equatable {
        case link(String)   // magnet or http(s) URL to a .torrent
        case file(Data)     // raw .torrent bytes
        var body: Data { switch self { case .link(let s): return Data(s.utf8); case .file(let d): return d } }
    }

    struct PendingAdd: Equatable {
        let source: AddSource
        let name: String
        let files: [TorrentFile]
    }

    struct EngineUnavailable: Error {}

    // MARK: - Settings (UserDefaults)
    static let downloadDirKey = "torrentDownloadDir"
    static let stopAtRatio1Key = "torrentStopAtRatio1"
    static let rateDownKey = "torrentRateDownKBps"   // canonical KB/s; 0 = unlimited
    static let rateUpKey = "torrentRateUpKBps"
    /// Display unit for the two speed-limit fields ("kb" | "mb"), shared by both.
    /// UI-only: the stored rate stays canonical KB/s, so there is no migration.
    static let rateUnitKey = "torrentRateUnit"
    static let advancedInfoKey = "torrentAdvancedInfo" // legacy key (per-row detail retired)
    static let showWhenEmptyKey = "torrentShowWhenEmpty" // render the empty add-card with zero torrents

    private var downloadFolder: URL {
        if let p = UserDefaults.standard.string(forKey: Self.downloadDirKey), !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
    private var stopAtRatio1: Bool { UserDefaults.standard.bool(forKey: Self.stopAtRatio1Key) }
    private var rateDownBps: Int? { let k = UserDefaults.standard.integer(forKey: Self.rateDownKey); return k > 0 ? k * 1000 : nil }
    private var rateUpBps: Int? { let k = UserDefaults.standard.integer(forKey: Self.rateUpKey); return k > 0 ? k * 1000 : nil }

    private var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.storageIdentifier
        return base.appendingPathComponent(id, isDirectory: true)
    }
    private var persistenceDir: URL { supportDir.appendingPathComponent("torrent-session", isDirectory: true) }
    private var persistFile: URL { supportDir.appendingPathComponent("torrents.json") }
    private var removalsFile: URL { supportDir.appendingPathComponent("torrent-removals.json") }

    // MARK: - Engine lifecycle
    private var engineStartTask: Task<Void, Error>?
    func ensureEngine(binaryOverride: URL? = nil) async throws {
        engineWanted = true
        try await joinEngineStart(binaryOverride: binaryOverride)
    }

    private func joinEngineStart(binaryOverride: URL? = nil) async throws {
        if client != nil, process.isRunning { return }
        // Serialize starts: a cold .torrent open can call this while launch restore()
        // is already starting the engine. Two starts on the SHARED process kill each
        // other (start #2's stop() drops start #1's half-boot; start #1's failed
        // waitForHealth then stop()s start #2's healthy engine). Everyone awaits the
        // same in-flight start instead of racing a second process.start.
        if let inFlight = engineStartTask { try await inFlight.value; return }
        let task = Task { try await self.startEngine(binaryOverride: binaryOverride) }
        engineStartTask = task
        defer { engineStartTask = nil }
        try await task.value
    }

    /// Download the engine the moment the user opts INTO torrents — from the
    /// what's-new banner, onboarding or the settings toggle — instead of at
    /// first use. By the time something urgent needs downloading, the engine
    /// is already in place; the in-module enable card stays as the fallback
    /// (and the retry path if this background fetch fails).
    func prefetchEngineIfNeeded() {
        guard installer.installedBinaryURL() == nil else { return }
        switch installer.state {
        case .downloading, .verifying: return   // already on its way
        default: break
        }
        Task { await installer.install() }
    }

    private func startEngine(binaryOverride: URL?) async throws {
        let binary: URL
        if let binaryOverride { binary = binaryOverride }
        else {
            await installer.updateIfNeeded()
            guard let installed = installer.installedBinaryURL() else { throw EngineUnavailable() }
            binary = installed
        }
        try FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: persistenceDir, withIntermediateDirectories: true)
        let (base, auth) = try await process.start(binary: binary, downloadFolder: downloadFolder,
                                                   persistenceDir: persistenceDir,
                                                   rateDownBps: rateDownBps, rateUpBps: rateUpBps)
        client = TorrentEngineClient(baseURL: base, basicAuth: auth, transport: URLSessionTransport())
        // SPEC: "A failed restart is retried" — any start after the first one hands out fresh ids.
        if sessionStarted, !torrents.isEmpty { remapPending = true }
        sessionStarted = true
        recoveryPending = false
        recoveryFailures = 0
        await applyRemovals()
    }

    /// SPEC: docs/spec.md "A removal holds until the engine lets go".
    private func applyRemovals() async {
        guard !removals.isEmpty, let client else { return }
        guard let before = await listLoaded(client) else {
            Self.log.error("the torrent engine did not list its torrents; \(self.removals.pending.count, privacy: .public) removal(s) stay pending")
            return
        }
        for removal in removals.pending
        where removals.contains(removal.infoHash)
            && before.contains(where: { $0.infoHash.caseInsensitiveCompare(removal.infoHash) == .orderedSame }) {
            do {
                if removal.deleteFiles { try await client.delete(id: removal.infoHash) }
                else { try await client.forget(id: removal.infoHash) }
            } catch {
                Self.log.error("removing torrent \(removal.infoHash, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
        let after: [ListedTorrent]
        if before.isEmpty { after = [] }
        else {
            do { after = try await client.list() } catch {
                Self.log.error("the torrent engine did not list its torrents after removing: \(String(describing: error), privacy: .public)")
                return
            }
        }
        for done in removals.settle(listed: after.map(\.infoHash)) where !done.deleteFiles {
            if let folder = done.outputFolder, let files = done.placeholders {
                removePlaceholders(outputFolder: folder, files: files)
            }
        }
        persistRemovals()
        if !removals.isEmpty {
            let held = removals.pending.map(\.infoHash).joined(separator: ", ")
            Self.log.error("the torrent engine still holds removed torrents \(held, privacy: .public); retrying at the next engine start")
        }
    }

    func stopEngine() {
        pollTask?.cancel(); pollTask = nil
        pathMonitor?.cancel(); pathMonitor = nil
        process.stop()
        client = nil
        engineWanted = false
        recoveryPending = false
        recoveryFailures = 0
    }

    /// Restart the engine after it died and re-map rows to the new session's ids
    /// (the new engine reloads the same persistence dir but assigns fresh ids). Rows
    /// the engine no longer holds are dropped. Returns false when no engine came up;
    /// polling then retries on its own.
    @discardableResult
    private func recoverEngine() async -> Bool {
        recoveryPending = true
        lastRecoveryAttempt = uptime
        client = nil                       // force ensureEngine to start a fresh process
        var failure: Error?
        do { try await joinEngineStart() } catch { failure = error }
        if !engineWanted {
            process.stop(); client = nil
            recoveryPending = false
            return false
        }
        guard let client else {
            recoveryFailures += 1
            let wait = Int(EngineRetry.delay(afterFailures: recoveryFailures))
            Self.log.error("the torrent engine did not start (\(String(describing: failure), privacy: .public)); next try in \(wait) s")
            return false
        }
        remapPending = true
        let known = Set(torrents.map(\.infoHash))
        remap(await listOnceLoaded(client), known: known)
        return true
    }

    /// SPEC: "Recovery keeps rows" — an empty early list would also erase torrents.json.
    /// Only rows in `known` (present before the list was requested) may be dropped.
    private func remap(_ listed: [ListedTorrent], known: Set<String>) {
        guard !listed.isEmpty else { return }
        remapPending = false
        torrents = torrents.compactMap { row in
            guard let current = listed.first(where: { $0.infoHash == row.infoHash }) else {
                return known.contains(row.infoHash) ? nil : row
            }
            var r = row; r.id = current.id; r.stats = nil; return r
        }
        persist()
    }

    /// A running engine for a user action, started if it is down but still wanted.
    private func readyClient() async -> TorrentEngineClient? {
        if engineWanted, client == nil || !process.isRunning { try? await joinEngineStart() }
        return client
    }

    /// The engine addresses a torrent by id or info hash alike; the hash survives a restart.
    private func engineKey(_ id: String) -> String {
        torrents.first(where: { $0.id == id })?.infoHash ?? id
    }

    // MARK: - Add flow
    func fetchFiles(source: AddSource, binaryOverride: URL? = nil) async throws -> PendingAdd {
        addsInFlight += 1
        defer { addsInFlight -= 1 }
        try await ensureEngine(binaryOverride: binaryOverride)
        guard let client else { throw EngineUnavailable() }
        let r = try await client.addListOnly(body: source.body)
        // Reject a torrent whose member paths would escape the output folder (../,
        // absolute, NUL) before it can write anything — don't trust the engine alone.
        guard !TorrentLayout.hasUnsafePath(r.files.map { $0.name }) else { throw EngineUnavailable() }
        return PendingAdd(source: source, name: r.name, files: r.files)
    }

    func confirmAdd(_ pending: PendingAdd, selectedIndices: Set<Int>, outputFolder: URL? = nil) async throws {
        addsInFlight += 1
        defer { addsInFlight -= 1 }
        try await ensureEngine()
        guard let client else { throw EngineUnavailable() }
        // Multi-file torrents are nested under a folder named after the torrent so
        // their loose files don't scatter into the chosen folder (rqbit writes file
        // paths relative to the content root, without the torrent name). Single-file
        // torrents write straight into the chosen folder.
        let base = outputFolder ?? downloadFolder
        let folder = TorrentLayout.subfolder(torrentName: pending.name, fileCount: pending.files.count)
            .map { base.appendingPathComponent($0, isDirectory: true) } ?? base
        let added = try await client.add(body: pending.source.body, outputFolder: folder.path)
        if removals.contains(added.infoHash) {   // added back: the old removal must not forget it
            removals.cancel(infoHash: added.infoHash)
            persistRemovals()
        }
        guard let id = added.id else { throw EngineUnavailable() }
        var files = pending.files
        for i in files.indices { files[i].selected = selectedIndices.contains(files[i].index) }
        let fromMagnet: Bool = {
            if case .link(let s) = pending.source { return s.lowercased().hasPrefix("magnet:") }
            return false
        }()
        let item = TorrentItem(id: id, infoHash: added.infoHash, name: added.name,
                               files: files, outputFolder: folder.path, fromMagnet: fromMagnet)
        // Dedup: rqbit returns the EXISTING id for a duplicate add (overwrite=true),
        // so update that row in place instead of appending a second row with the same
        // Identifiable id (which breaks ForEach + double-counts speeds/notifications).
        if let idx = torrents.firstIndex(where: { $0.infoHash == added.infoHash }) {
            torrents[idx] = item
        } else {
            torrents.append(item)
        }
        persist()
        startPolling()
        // Apply the file selection AFTER the row exists and is persisted, best-effort:
        // if it failed BEFORE the append (as it used to), a throw left the torrent
        // running in the engine with no row — invisible and unremovable from the UI.
        let allIndices = Set(pending.files.map { $0.index })
        if selectedIndices != allIndices {
            try? await client.setSelectedFiles(id: id, indices: Array(selectedIndices).sorted())
        }
    }

    // MARK: - Actions
    func pause(id: String) {
        if let i = torrents.firstIndex(where: { $0.id == id }) {
            torrents[i].optimisticPaused = true   // flip the button now, settle on poll
        }
        let key = engineKey(id)
        Task {
            do {
                guard let c = await readyClient() else { throw EngineUnavailable() }
                try await c.pause(id: key)
            } catch { clearOptimisticPause(key) }    // engine refused — drop the guess, trust truth
        }
    }
    func resume(id: String) {
        if let i = torrents.firstIndex(where: { $0.id == id }) {
            torrents[i].optimisticPaused = false
            torrents[i].pausedByPolicy = false
            torrents[i].seedPolicyOverridden = true
            // Clear the "files removed" flag: resuming re-downloads the missing
            // payload, and the next poll re-runs the deletion probe from scratch.
            torrents[i].filesMissing = false
            persist()
        }
        let key = engineKey(id)
        Task {
            do {
                guard let c = await readyClient() else { throw EngineUnavailable() }
                try await c.resume(id: key)
            } catch { clearOptimisticPause(key) }
        }
    }
    /// Drop the optimistic pause guess back to nil so the next poll adopts engine
    /// truth — otherwise a failed pause/resume call leaves the button lying forever.
    private func clearOptimisticPause(_ infoHash: String) {
        if let i = torrents.firstIndex(where: { $0.infoHash == infoHash }) { torrents[i].optimisticPaused = nil }
    }
    /// Include/exclude one file after the torrent was added. rqbit re-selects live
    /// (`update_only_files`), so switching a file on resumes downloading it and off
    /// stops it. Optimistic: flip the stored `selected` now, then tell the engine.
    func setFileSelected(id: String, fileIndex: Int, on: Bool) {
        guard let ti = torrents.firstIndex(where: { $0.id == id }),
              let fi = torrents[ti].files.firstIndex(where: { $0.index == fileIndex }) else { return }
        // rqbit accepts an empty selection (verified live: update_only_files [] → 200),
        // so deselecting the last file is fine — and consistent with the "none" bulk
        // button, which also empties it. The torrent then just idles until re-picked.
        torrents[ti].files[fi].selected = on
        let indices = torrents[ti].files.filter { $0.selected }.map { $0.index }.sorted()
        persist()
        let key = engineKey(id)
        Task { try? await readyClient()?.setSelectedFiles(id: key, indices: indices) }
    }
    /// Select or deselect every file at once — the expanded list's "all / none".
    func setAllFilesSelected(id: String, selected: Bool) {
        guard let ti = torrents.firstIndex(where: { $0.id == id }),
              !torrents[ti].files.isEmpty else { return }
        for i in torrents[ti].files.indices { torrents[ti].files[i].selected = selected }
        let indices = torrents[ti].files.filter { $0.selected }.map { $0.index }.sorted()
        persist()
        let key = engineKey(id)
        Task { try? await readyClient()?.setSelectedFiles(id: key, indices: indices) }
    }
    /// SPEC: docs/spec.md "A removal holds until the engine lets go".
    func remove(id: String, deleteFiles: Bool) {
        guard let row = torrents.first(where: { $0.id == id }) else { return }
        torrents.removeAll { $0.id == id }   // optimistic UI update
        expandedIds.remove(id)
        removals.add(infoHash: row.infoHash, deleteFiles: deleteFiles,
                     outputFolder: row.filesMissing ? row.outputFolder : nil,
                     placeholders: row.filesMissing
                        ? row.files.map { PendingTorrentRemoval.Placeholder(name: $0.name, lengthBytes: $0.lengthBytes) }
                        : nil)
        persistRemovals()
        persist()
        Task {
            if client == nil || !process.isRunning {
                do { try await joinEngineStart() } catch {
                    Self.log.error("the torrent engine did not start for a removal (\(String(describing: error), privacy: .public)); it stays pending")
                }
            }
            await applyRemovals()
            // Re-check AFTER the awaits: the user may have added a torrent meanwhile,
            // and stopping the engine would kill that fresh download.
            if addsInFlight == 0, torrents.isEmpty || !engineWanted { stopEngine() }
        }
    }

    private func removePlaceholders(outputFolder: String, files: [PendingTorrentRemoval.Placeholder]) {
        let fm = FileManager.default
        let placeholders = TorrentLayout.emptyPlaceholders(
            outputFolder: outputFolder, files: files.map { (name: $0.name, lengthBytes: $0.lengthBytes) },
            stat: { path in
                var st = Darwin.stat()
                guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
                return (size: Int64(st.st_size), blocks: Int64(st.st_blocks))
            })
        for path in placeholders {
            do {
                try fm.removeItem(atPath: path)
                Self.log.info("removed the engine's empty placeholder \(path, privacy: .public)")
            } catch {
                Self.log.error("could not remove the placeholder \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        guard files.count > 1, !placeholders.isEmpty else { return }
        let wrapper = URL(fileURLWithPath: outputFolder, isDirectory: true)
        let leftovers = fm.enumerator(at: wrapper, includingPropertiesForKeys: [.isDirectoryKey])?
            .contains { (($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory }) != true } ?? true
        if !leftovers { try? fm.removeItem(at: wrapper) }
    }
    /// Reveal the download in Finder, gracefully. rqbit writes a single-file
    /// torrent as `outputFolder/<file name>` and a multi-file one as
    /// `outputFolder/<torrent name>/…`, so the right target differs. Select the
    /// first candidate that actually exists; if neither does (renamed, moved,
    /// or still resolving), open the output folder itself instead of flashing a
    /// Finder window on a non-existent path.
    func revealInFinder(id: String) {
        guard let item = torrents.first(where: { $0.id == id }) else { return }
        let fm = FileManager.default
        let folder = URL(fileURLWithPath: item.outputFolder)
        // A single file's name — or, when a restore left us without file detail,
        // the torrent name (which for a single-file torrent IS the filename).
        // Select that exact file if it's on disk.
        let fileName = item.files.count == 1 ? item.files.first?.name
            : (item.files.isEmpty ? item.name : nil)
        if let fileName {
            let f = folder.appendingPathComponent(fileName)
            if fm.fileExists(atPath: f.path) {
                NSWorkspace.shared.activateFileViewerSelecting([f])
                return
            }
        }
        // Otherwise OPEN the torrent's own folder so its files are shown inside
        // it, not just the folder selected in its parent. Fall back to the
        // nearest existing ancestor if it isn't on disk yet.
        if fm.fileExists(atPath: folder.path) {
            NSWorkspace.shared.open(folder)
            return
        }
        var ancestor = folder.deletingLastPathComponent()
        while !fm.fileExists(atPath: ancestor.path), ancestor.pathComponents.count > 1 {
            ancestor = ancestor.deletingLastPathComponent()
        }
        NSWorkspace.shared.open(ancestor)
    }

    var aggregateDownBps: Int64 { torrents.compactMap { $0.stats?.downloadBps }.reduce(0, +) }
    var aggregateUpBps: Int64 { torrents.compactMap { $0.stats?.uploadBps }.reduce(0, +) }

    /// Independent download/upload signals for the menu-bar corner arrows: a
    /// non-paused torrent still fetching lights ↓ (steady — not tied to the
    /// instantaneous speed, so it doesn't flicker), a FINISHED torrent that is
    /// actively uploading lights ↑ (true seeding, not the incidental upload that
    /// rides along with a download). Both can be true at once — one torrent
    /// fetching while another seeds — which is the "↓↑" state. Both false when
    /// idle, paused, or empty.
    var menuBarTransfer: (down: Bool, up: Bool) {
        let active = torrents.filter {
            !($0.optimisticPaused ?? ($0.pausedByPolicy || $0.stats?.state == .paused))
        }
        guard !active.isEmpty else { return (false, false) }
        // An errored torrent isn't "downloading" — don't light the arrow for it.
        let down = active.contains { !($0.stats?.finished ?? false) && $0.stats?.state != .error }
        let up = active.contains { ($0.stats?.finished ?? false) && ($0.stats?.uploadBps ?? 0) > 0 }
        return (down, up)
    }

    /// Snapshot/demo seam (mirrors SystemStatsController.injectDemoHistory):
    /// preload rows so the active-list state renders under `--snapshot`.
    /// No engine is started and polling never runs.
    func loadDemo(_ items: [TorrentItem]) { torrents = items }

    // MARK: - Polling
    private func startPolling() {
        guard pollTask == nil else { return }
        stallWatch = TorrentStallWatch()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let interfaces = path.availableInterfaces.map(\.name)
            Task { @MainActor in self?.stallWatch.pathUpdated(online: online, interfaces: interfaces) }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func pollOnce() async {
        // The engine died (crash / OOM / external kill) but we still hold a client:
        // every stats call would fail silently and rows would freeze at stale numbers
        // forever. Restart it and re-map rows to the new session's ids.
        if !torrents.isEmpty,
           (client != nil && !process.isRunning)
            || (client == nil && recoveryPending
                && uptime - lastRecoveryAttempt >= EngineRetry.delay(afterFailures: recoveryFailures)) {
            await recoverEngine()
        }
        guard let client else { return }
        if remapPending {
            let known = Set(torrents.map(\.infoHash))
            remap((try? await client.list()) ?? [], known: known)
        }
        for i in torrents.indices where i < torrents.count {
            let id = torrents[i].infoHash
            guard let stats = try? await client.stats(id: id) else { continue }
            guard i < torrents.count, torrents[i].infoHash == id else { continue }
            torrents[i].stats = stats
            // Optimistic pause settled: once the engine's own state matches what
            // the button already shows, drop the override and trust engine truth.
            if let optimistic = torrents[i].optimisticPaused,
               (stats.state == .paused) == optimistic {
                torrents[i].optimisticPaused = nil
            }
            if stats.finished && !torrents[i].notifiedDone {
                torrents[i].notifiedDone = true
                // Whether the banner may promise continued sharing is decided
                // here, from the engine's own state: a torrent the user already
                // paused is complete and quiet, and saying otherwise would be a
                // small lie in the one place the user is looking.
                let seeding = stats.state != .paused
                    && torrents[i].optimisticPaused != true
                    && !torrents[i].pausedByPolicy
                notify(.finished(stats: stats, seeding: seeding), name: torrents[i].name)
                persist()   // persist so a finished torrent isn't re-notified next launch
            }
            // SPEC: docs/spec.md "A seeding torrent whose file is gone is paused".
            if TorrentLayout.watchesPayload(
                   state: stats.state, progressBytes: stats.progressBytes,
                   flagged: torrents[i].filesMissing,
                   paused: torrents[i].optimisticPaused == true || torrents[i].pausedByPolicy),
               TorrentLayout.payloadMissing(
                   outputFolder: torrents[i].outputFolder,
                   fileNames: torrents[i].files.map { $0.name },
                   exists: { FileManager.default.fileExists(atPath: $0) }) {
                torrents[i].filesMissing = true
                torrents[i].optimisticPaused = true   // reflect the pause in the UI at once
                persist()
                try? await client.pause(id: id)
                guard i < torrents.count, torrents[i].infoHash == id else { continue }
            }
            if !torrents[i].pausedByPolicy, !torrents[i].seedPolicyOverridden,
               SeedPolicy.shouldPause(stats: stats, stopAtRatio1: stopAtRatio1) {
                torrents[i].pausedByPolicy = true
                // The give-back the user asked for is done. That is the end of
                // the torrent's life in Hop and worth saying out loud, exactly
                // once — the flag above is what keeps it to once.
                notify(.seedingStopped(stats: stats), name: torrents[i].name)
                try? await client.pause(id: id)
            }
        }
        // SPEC: "Stall recovery" in the torrent engine section.
        let signal = TorrentStallWatch.assess(torrents.map { row in
            (row.stats, row.filesMissing
                || (row.optimisticPaused ?? (row.pausedByPolicy || row.stats?.state == .paused)))
        })
        if stallWatch.observe(signal, now: Date(timeIntervalSinceReferenceDate: uptime)),
           !(await recoverEngine()) {
            stallWatch.restartFailed()
        }
    }

    /// One banner per torrent event, respecting the app's alert setting.
    /// Look at Sources/Hop/Alerts.swift for how the app posts notifications and
    /// reuse that path (UNUserNotificationCenter). Silent if alerts are off.
    ///
    /// The body is ALWAYS supplied. Passing a title alone let the notification
    /// helper fall back to its default text, and a finished torrent announced
    /// itself with the timer's "the timer has finished".
    private func notify(_ banner: TorrentBanner, name: String) {
        let lang = L10n.current
        let size = SizeFormatting.sizeText(banner.bytes)
        let key: L10nKey
        switch banner {
        case .downloadedSeeding: key = .notifTorrentDownloadedSeeding
        case .downloaded: key = .notifTorrentDownloaded
        case .seedingFinished: key = .notifTorrentSeedingFinished
        }
        let body = L10n.fill(key, lang, size)
        Alerts.fire(mode: AlertMode.current,
                    title: Substitutions.isolate(name, or: L10n.t(.notifTitle, lang)),
                    body: body)
    }

    // MARK: - Persistence
    private struct PersistedFile: Codable {
        let index: Int; let name: String; let lengthBytes: Int64; let selected: Bool
    }
    private struct Persisted: Codable {
        let infoHash: String; let name: String; let outputFolder: String; let files: [PersistedFile]
        let fromMagnet: Bool?    // optional: older torrents.json files predate these fields
        let notifiedDone: Bool?  // so a finished torrent doesn't re-fire its notification every launch
        let seedPolicyOverridden: Bool?  // so a "keep seeding" override survives restarts
        let filesMissing: Bool?
    }
    private func persist() {
        let rows = torrents.map { t in
            Persisted(infoHash: t.infoHash, name: t.name, outputFolder: t.outputFolder,
                      files: t.files.map { PersistedFile(index: $0.index, name: $0.name, lengthBytes: $0.lengthBytes, selected: $0.selected) },
                      fromMagnet: t.fromMagnet, notifiedDone: t.notifiedDone,
                      seedPolicyOverridden: t.seedPolicyOverridden, filesMissing: t.filesMissing)
        }
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(rows).write(to: persistFile)
    }
    private func persistRemovals() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        do { try JSONEncoder().encode(removals).write(to: removalsFile) } catch {
            Self.log.error("torrent-removals.json was not written: \(String(describing: error), privacy: .public)")
        }
    }
    private var sessionHoldsTorrents: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: persistenceDir.path)) ?? [])
            .contains { $0.hasSuffix(".torrent") }
    }

    /// Right after start the engine may list nothing while loading its session; retries ~3 s.
    private func listOnceLoaded(_ client: TorrentEngineClient) async -> [ListedTorrent] {
        await listLoaded(client) ?? []
    }

    private func listLoaded(_ client: TorrentEngineClient) async -> [ListedTorrent]? {
        var listed = try? await client.list()
        var tries = 0
        while listed?.isEmpty ?? true, tries < 15 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if let answer = try? await client.list() { listed = answer }
            tries += 1
        }
        return listed
    }

    func restore() async {
        let saved = (try? Data(contentsOf: persistFile))
            .flatMap { try? JSONDecoder().decode([Persisted].self, from: $0) } ?? []
        guard !saved.isEmpty || !removals.isEmpty || sessionHoldsTorrents else { return }
        let vanished = Set(saved.filter { s in
            s.filesMissing ?? false
                || ((s.notifiedDone ?? false) && TorrentLayout.payloadMissing(
                    outputFolder: s.outputFolder, fileNames: s.files.map(\.name),
                    exists: { FileManager.default.fileExists(atPath: $0) }))
        }.map(\.infoHash))
        do {
            try await ensureEngine()
            guard let client else { return }
            let listed = removals.visible(await listOnceLoaded(client), infoHash: \.infoHash)
            // The engine is the source of truth for what's actually downloading:
            // show every torrent it holds, enriched with saved file/selection detail
            // when we have it. A torrent in the engine but missing from torrents.json
            // (e.g. a lost write) still appears — just without its per-file breakdown
            // until re-added — instead of running invisibly.
            // Snapshot rows already present (a fresh add that raced this restore) so
            // we MERGE rather than overwrite — the old `torrents = listed.map` blew a
            // concurrent add away, rebuilding it with an empty file list.
            let existingRows = torrents
            torrents = listed.map { current in
                if let existing = existingRows.first(where: { $0.infoHash == current.infoHash }) {
                    return existing   // keep the live row (accurate id/files/source/flags)
                }
                if let s = saved.first(where: { $0.infoHash == current.infoHash }) {
                    let files = s.files.map { TorrentFile(index: $0.index, name: $0.name, lengthBytes: $0.lengthBytes, selected: $0.selected) }
                    var item = TorrentItem(id: current.id, infoHash: s.infoHash, name: s.name, files: files, outputFolder: s.outputFolder, fromMagnet: s.fromMagnet ?? false)
                    item.notifiedDone = s.notifiedDone ?? false             // don't re-notify a finished torrent every launch
                    item.seedPolicyOverridden = s.seedPolicyOverridden ?? false  // keep a "keep seeding" override
                    item.filesMissing = vanished.contains(s.infoHash)
                    return item
                }
                return TorrentItem(id: current.id, infoHash: current.infoHash, name: current.name, files: [], outputFolder: current.outputFolder)
            }
            guard !torrents.isEmpty else {
                if addsInFlight == 0 { stopEngine() }
                return
            }
            persist()
            startPolling()
            for row in torrents where row.filesMissing { try? await client.pause(id: row.infoHash) }
        } catch {}
    }
}
