import Combine
import Foundation
import HopCore
import AppKit

@MainActor
final class TorrentController: ObservableObject {
    let installer = TorrentEngineInstaller()
    private let process = TorrentEngineProcess()
    private var client: TorrentEngineClient?
    private var pollTask: Task<Void, Never>?

    @Published private(set) var torrents: [TorrentItem] = []

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
        forwarders.append(installer.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        })
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
        /// Not persisted — rqbit remembers its own paused state across restarts.
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
    static let rateDownKey = "torrentRateDownKBps"   // KB/s in the UI; 0 = unlimited
    static let rateUpKey = "torrentRateUpKBps"
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
        let id = Bundle.main.bundleIdentifier ?? "com.antonshakirov.minimo"
        return base.appendingPathComponent(id, isDirectory: true)
    }
    private var persistenceDir: URL { supportDir.appendingPathComponent("torrent-session", isDirectory: true) }
    private var persistFile: URL { supportDir.appendingPathComponent("torrents.json") }

    // MARK: - Engine lifecycle
    private var engineStartTask: Task<Void, Error>?
    func ensureEngine(binaryOverride: URL? = nil) async throws {
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
        else if let installed = installer.installedBinaryURL() { binary = installed }
        else { throw EngineUnavailable() }
        try FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: persistenceDir, withIntermediateDirectories: true)
        let (base, auth) = try await process.start(binary: binary, downloadFolder: downloadFolder,
                                                   persistenceDir: persistenceDir,
                                                   rateDownBps: rateDownBps, rateUpBps: rateUpBps)
        client = TorrentEngineClient(baseURL: base, basicAuth: auth, transport: URLSessionTransport())
    }

    func stopEngine() {
        pollTask?.cancel(); pollTask = nil
        process.stop()
        client = nil
    }

    /// Restart the engine after it died and re-map rows to the new session's ids
    /// (the new engine reloads the same persistence dir but assigns fresh ids). Rows
    /// the engine no longer holds are dropped. Best-effort — a failed restart just
    /// leaves `client` nil and the next poll tries again.
    private func recoverEngine() async {
        client = nil                       // force ensureEngine to start a fresh process
        try? await ensureEngine()
        guard let client else { return }
        let listed = (try? await client.list()) ?? []
        torrents = torrents.compactMap { row in
            guard let current = listed.first(where: { $0.infoHash == row.infoHash }) else { return nil }
            var r = row; r.id = current.id; r.stats = nil; return r
        }
        persist()
    }

    // MARK: - Add flow
    func fetchFiles(source: AddSource, binaryOverride: URL? = nil) async throws -> PendingAdd {
        try await ensureEngine(binaryOverride: binaryOverride)
        guard let client else { throw EngineUnavailable() }
        let r = try await client.addListOnly(body: source.body)
        // Reject a torrent whose member paths would escape the output folder (../,
        // absolute, NUL) before it can write anything — don't trust the engine alone.
        guard !TorrentLayout.hasUnsafePath(r.files.map { $0.name }) else { throw EngineUnavailable() }
        return PendingAdd(source: source, name: r.name, files: r.files)
    }

    func confirmAdd(_ pending: PendingAdd, selectedIndices: Set<Int>, outputFolder: URL? = nil) async throws {
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
        if let idx = torrents.firstIndex(where: { $0.id == id || $0.infoHash == added.infoHash }) {
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
        Task {
            do { try await client?.pause(id: id) }
            catch { clearOptimisticPause(id) }    // engine refused — drop the guess, trust truth
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
        }
        Task {
            do { try await client?.resume(id: id) }
            catch { clearOptimisticPause(id) }
        }
    }
    /// Drop the optimistic pause guess back to nil so the next poll adopts engine
    /// truth — otherwise a failed pause/resume call leaves the button lying forever.
    private func clearOptimisticPause(_ id: String) {
        if let i = torrents.firstIndex(where: { $0.id == id }) { torrents[i].optimisticPaused = nil }
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
        Task { try? await client?.setSelectedFiles(id: id, indices: indices) }
    }
    /// Select or deselect every file at once — the expanded list's "all / none".
    func setAllFilesSelected(id: String, selected: Bool) {
        guard let ti = torrents.firstIndex(where: { $0.id == id }),
              !torrents[ti].files.isEmpty else { return }
        for i in torrents[ti].files.indices { torrents[ti].files[i].selected = selected }
        let indices = torrents[ti].files.filter { $0.selected }.map { $0.index }.sorted()
        persist()
        Task { try? await client?.setSelectedFiles(id: id, indices: indices) }
    }
    func remove(id: String, deleteFiles: Bool) {
        torrents.removeAll { $0.id == id }   // optimistic UI update
        expandedIds.remove(id)
        persist()
        let c = client
        Task {
            if deleteFiles { try? await c?.delete(id: id) } else { try? await c?.forget(id: id) }
            // Re-check emptiness AFTER the await: during the round-trip the user may
            // have added a new torrent that reused the still-running engine — stopping
            // it here would kill that fresh download. Only stop if still empty.
            if torrents.isEmpty { stopEngine() }
        }
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
        // Otherwise OPEN the torrent's own folder so its files are shown inside it,
        // not just the folder selected in its parent (Anton: reveal opened plain
        // Finder). Fall back to the nearest existing ancestor if it isn't on disk yet.
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

    /// What the menu bar should signal at a glance. `.downloading` whenever a
    /// non-paused torrent is still fetching (steady — not tied to the instantaneous
    /// speed, so the arrow doesn't flicker); `.seeding` once everything is done but
    /// still actually uploading; `.none` when idle, paused, or empty.
    enum MenuBarActivity { case downloading, seeding, none }
    var menuBarActivity: MenuBarActivity {
        let active = torrents.filter {
            !($0.optimisticPaused ?? ($0.pausedByPolicy || $0.stats?.state == .paused))
        }
        guard !active.isEmpty else { return .none }
        // An errored torrent isn't "downloading" — don't light the menu-bar arrow for it.
        if active.contains(where: { !($0.stats?.finished ?? false) && $0.stats?.state != .error }) {
            return .downloading
        }
        return aggregateUpBps > 0 ? .seeding : .none
    }

    /// Snapshot/demo seam (mirrors SystemStatsController.injectDemoHistory):
    /// preload rows so the active-list state renders under `--snapshot`.
    /// No engine is started and polling never runs.
    func loadDemo(_ items: [TorrentItem]) { torrents = items }

    // MARK: - Polling
    private func startPolling() {
        guard pollTask == nil else { return }
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
        if client != nil, !process.isRunning, !torrents.isEmpty {
            await recoverEngine()
        }
        guard let client else { return }
        for i in torrents.indices where i < torrents.count {
            let id = torrents[i].id
            guard let stats = try? await client.stats(id: id) else { continue }
            guard i < torrents.count, torrents[i].id == id else { continue }
            torrents[i].stats = stats
            // Optimistic pause settled: once the engine's own state matches what
            // the button already shows, drop the override and trust engine truth.
            if let optimistic = torrents[i].optimisticPaused,
               (stats.state == .paused) == optimistic {
                torrents[i].optimisticPaused = nil
            }
            if stats.finished && !torrents[i].notifiedDone {
                torrents[i].notifiedDone = true
                notifyDone(name: torrents[i].name)
                persist()   // persist so a finished torrent isn't re-notified next launch
            }
            // The user deleted the payload out from under an active download (via
            // Finder, not via Hop): rqbit then keeps writing into an orphaned inode
            // or errors out, while the row shows steady progress into nothing. Detect
            // the vanished payload, pause the torrent, and flag the row so the user
            // can resume (re-download) or remove. Guard on progressBytes > 0 so we
            // never mistake "rqbit hasn't written the first byte yet" for deletion,
            // and only for a live, non-finished, non-paused row.
            if !torrents[i].filesMissing,
               !stats.finished,
               stats.state == .live,
               torrents[i].optimisticPaused != true,
               !torrents[i].pausedByPolicy,
               stats.progressBytes > 0,
               TorrentLayout.payloadMissing(
                   outputFolder: torrents[i].outputFolder,
                   fileNames: torrents[i].files.map { $0.name },
                   exists: { FileManager.default.fileExists(atPath: $0) }) {
                torrents[i].filesMissing = true
                torrents[i].optimisticPaused = true   // reflect the pause in the UI at once
                persist()
                try? await client.pause(id: id)
            }
            if !torrents[i].pausedByPolicy, !torrents[i].seedPolicyOverridden,
               SeedPolicy.shouldPause(stats: stats, stopAtRatio1: stopAtRatio1) {
                torrents[i].pausedByPolicy = true
                try? await client.pause(id: id)
            }
        }
    }

    /// One "downloaded" banner per torrent, respecting the app's alert setting.
    /// Look at Sources/Hop/Alerts.swift for how the app posts notifications and
    /// reuse that path (UNUserNotificationCenter). Silent if alerts are off.
    private func notifyDone(name: String) {
        Alerts.fire(mode: AlertMode.current, title: name)
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
    }
    private func persist() {
        let rows = torrents.map { t in
            Persisted(infoHash: t.infoHash, name: t.name, outputFolder: t.outputFolder,
                      files: t.files.map { PersistedFile(index: $0.index, name: $0.name, lengthBytes: $0.lengthBytes, selected: $0.selected) },
                      fromMagnet: t.fromMagnet, notifiedDone: t.notifiedDone,
                      seedPolicyOverridden: t.seedPolicyOverridden)
        }
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(rows).write(to: persistFile)
    }

    func restore() async {
        let saved = (try? Data(contentsOf: persistFile))
            .flatMap { try? JSONDecoder().decode([Persisted].self, from: $0) } ?? []
        guard !saved.isEmpty else { return }
        do {
            try await ensureEngine()
            guard let client else { return }
            // The engine may still be loading its persisted session right after
            // start, so list() can briefly come back empty — retry (~3s) until the
            // torrents surface, instead of restoring nothing and leaving the panel
            // blank while the engine quietly resumes them.
            var listed = (try? await client.list()) ?? []
            var tries = 0
            while listed.isEmpty, tries < 15 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                listed = (try? await client.list()) ?? []
                tries += 1
            }
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
                    return item
                }
                return TorrentItem(id: current.id, infoHash: current.infoHash, name: current.name, files: [], outputFolder: current.outputFolder)
            }
            if !torrents.isEmpty { persist(); startPolling() }
        } catch {}
    }
}
