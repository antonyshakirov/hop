import AppKit
import Combine
import HopCore
import os

/// The uninstaller's machinery: find what an app left behind, move it to the
/// trash, and say what stayed.
///
/// Every decision about WHICH paths belong to the app lives in
/// `HopCore.AppUninstall` and is unit-tested. This layer only touches the disk:
/// existence, sizes, quitting the app, `launchctl`, and the move to the trash.
@MainActor
final class UninstallController: ObservableObject {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "Uninstall")

    /// One found trace, with the size it actually occupies and whether the user
    /// wants it gone.
    struct Trace: Identifiable {
        let id = UUID()
        let candidate: AppUninstall.Candidate
        let bytes: Int64
        var ticked: Bool

        var path: String { candidate.path }
        var kind: AppUninstall.Kind { candidate.kind }
        var name: String { (path as NSString).lastPathComponent }
    }

    /// One app's caches, added up.
    struct CacheOwner: Identifiable {
        let identifier: String
        /// The app's name when the system still knows it, the raw identifier when
        /// it does not — an unknown owner is a leftover, and saying so is honest.
        let name: String
        let appPath: String?
        let paths: [String]
        let bytes: Int64
        var ticked: Bool

        var id: String { identifier }
    }

    /// One app the window offers to remove.
    struct InstalledApp: Identifiable {
        let path: String
        let name: String
        let identifier: String
        let icon: NSImage
        /// The bundle itself, and everything of its that a removal would take.
        /// Both are shown, because "1.4 GB" answers a different question from
        /// "1.2 GB of app plus 200 MB it saved up" (Anton, 2026-07-30). Measured
        /// after the list appears, so an empty size means "not weighed yet".
        var appBytes: Int64 = 0
        var traceBytes: Int64 = 0

        var id: String { path }
        var totalBytes: Int64 { appBytes + traceBytes }
        var weighed: Bool { appBytes > 0 || traceBytes > 0 }
    }

    /// How the list of installed apps is ordered.
    enum AppSort: String, CaseIterable {
        case name, size
    }

    /// One installer file, with the tick the user puts on it.
    struct InstallerFile: Identifiable {
        let found: InstallerFiles.Found
        var ticked: Bool

        var id: String { found.path }
    }

    struct Target {
        let path: String
        let name: String
        let bundleIdentifier: String
        let icon: NSImage
    }

    /// What happened, including what could not be touched.
    struct Report {
        var trashed: Int
        var bytes: Int64
        var failed: [String]
        var stayed: [AppUninstall.Remainder]
        /// Paths macOS itself refused: containers, autosaved data and cookies are
        /// protected, and only Full Disk Access opens them. Reported apart from a
        /// real failure, because the fix is a switch in System Settings rather than
        /// anything wrong with the run.
        var needsFullDisk: [String] = []
    }

    /// What the window is doing with the app it was given.
    /// Two jobs, two entry points. Installers used to be a mode of their own and
    /// that was one screen too many for something this obvious (Anton, 2026-07-30):
    /// they belong beside the caches, offered while you are already cleaning up.
    enum Mode: String, CaseIterable, Equatable {
        /// Remove an app and everything it left.
        case uninstall
        /// Keep the apps: caches, installers, leftovers of apps long gone, trash.
        case clean
    }

    enum State: Equatable {
        case empty
        case scanning
        case found
        case working
        case done
    }

    @Published var mode: Mode = .uninstall {
        didSet { if oldValue != mode { rescanForMode() } }
    }
    @Published private(set) var state: State = .empty
    /// Installers found on disk (the `installers` mode).
    @Published var installers: [InstallerFile] = []
    /// Every app that has a cache, biggest first (the `cache` mode with no app
    /// chosen). Anton, 2026-07-30: a cache mode that makes you drop apps one by
    /// one answers the wrong question — the question is "who is holding my disk".
    @Published var cacheOwners: [CacheOwner] = []
    /// Apps that can be removed, so the window does not depend on dragging.
    @Published var installedApps: [InstalledApp] = []
    /// Name or size, remembered between openings.
    @Published var appSort: AppSort = AppSort(
        rawValue: UserDefaults.standard.string(forKey: "uninstallAppSort") ?? "") ?? .name {
        didSet {
            UserDefaults.standard.set(appSort.rawValue, forKey: "uninstallAppSort")
            installedApps = Self.sorted(installedApps, by: appSort)
        }
    }
    /// Data of apps that are not on this Mac any more.
    @Published var leftovers: [CacheOwner] = []
    /// Big app data that only the app itself can clear safely.
    @Published var heavyData: [CacheOwner] = []
    @Published private(set) var trashBytes: Int64 = 0
    @Published private(set) var trashItems: Int = 0
    /// What the cache mode deliberately leaves alone, with its size, so the window
    /// can say why 25 GB is still there.
    @Published private(set) var mixed: [Trace] = []
    @Published private(set) var target: Target?
    @Published var traces: [Trace] = []
    @Published private(set) var report: Report?
    /// Set when the app refuses to quit — removing a running app leaves half of it
    /// behind and relaunches the rest.
    @Published private(set) var blockedByRunning = false
    /// True while the clean-up walk is still running, so the window can say so
    /// instead of looking empty.
    @Published private(set) var scanning = false
    private var cleanTask: Task<Void, Never>?
    private var appWeighing: Task<Void, Never>?

    var totalBytes: Int64 { traces.filter(\.ticked).reduce(0) { $0 + $1.bytes } }
    var needsAdmin: Bool {
        traces.contains { $0.ticked && AppUninstall.needsAdmin(path: $0.path, kind: $0.kind) }
    }

    // MARK: - Picking an app

    /// Accepts a dropped or picked path. Anything that is not an app bundle is
    /// ignored rather than guessed at.
    func choose(path: String) {
        guard path.hasSuffix(".app") else { return }
        let url = URL(fileURLWithPath: path)
        let bundle = Bundle(url: url)
        target = Target(
            path: path,
            name: FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: ""),
            bundleIdentifier: bundle?.bundleIdentifier ?? "",
            icon: NSWorkspace.shared.icon(forFile: path))
        report = nil
        blockedByRunning = false
        scan()
    }

    func promptToChoose() {
        guard !Snapshot.active else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        choose(path: url.path)
    }

    /// Opens the window straight in one mode — the panel offers the three as
    /// separate actions, so the window must not start on a tab nobody picked.
    func start(mode: Mode) {
        self.mode = mode
        target = nil
        report = nil
        rescanForMode()
    }

    /// Back to choosing: the app that was picked is forgotten and the list is
    /// there again, filled if it never was.
    func back() {
        reset()
        if mode == .uninstall, installedApps.isEmpty { listInstalledApps() }
    }

    func reset() {
        target = nil
        traces = []
        report = nil
        blockedByRunning = false
        state = .empty
    }

    // MARK: - Scanning

    private func scan() {
        guard let target else { return }
        state = .scanning
        let found = Self.scanTraces(identifier: target.bundleIdentifier,
                                   name: target.name,
                                   appPath: target.path)
        switch mode {
        case .uninstall:
            traces = found
            mixed = []
        case .clean:
            // only what macOS calls a cache, plus the sandboxed one inside the
            // container; the container itself is listed as untouchable, with its
            // size, rather than quietly skipped
            var caches = found.filter {
                AppUninstall.isDisposableCache(path: $0.path, kind: $0.kind)
            }
            for trace in found where AppUninstall.holdsMixedData(trace.kind) {
                let inner = AppUninstall.containerCache(trace.path)
                if FileManager.default.fileExists(atPath: inner) {
                    caches.append(Trace(candidate: AppUninstall.Candidate(
                        path: inner, kind: trace.kind, match: .identifier),
                        bytes: Self.size(of: inner), ticked: true))
                }
            }
            traces = caches
            mixed = found.filter { AppUninstall.holdsMixedData($0.kind) }
        }
        state = traces.isEmpty ? .empty : .found
    }

    private func rescanForMode() {
        // A snapshot render stages its own lists; a rescan here would wipe them
        // and walk somebody's real disk to draw a product picture.
        guard !Snapshot.active else { return }
        report = nil
        switch mode {
        case .clean:
            startCleanScan()
        case .uninstall:
            if target != nil { scan() } else { listInstalledApps() }
        }
    }

    /// The clean-up scan, off the main thread and section by section.
    ///
    /// It walks every cache folder, every container and the trash, adding up
    /// sizes — seconds of disk on a full Mac. Doing that before the window
    /// appeared meant clicking "clear the cache" and staring at nothing (Anton,
    /// 2026-07-30). Now the window is there immediately and each list drops in
    /// when it is ready: installers first because they are instant, the
    /// containers last because they are the slowest thing here.
    private func startCleanScan() {
        cleanTask?.cancel()
        installers = []
        cacheOwners = []
        leftovers = []
        heavyData = []
        trashBytes = 0
        trashItems = 0
        scanning = true
        cleanTask = Task { [weak self] in
            let installed = await Task.detached(priority: .utility) {
                Set(Self.installedIdentifiers())
            }.value
            guard !Task.isCancelled, let self else { return }

            let found = await Task.detached(priority: .utility) { Self.rawInstallers() }.value
            guard !Task.isCancelled else { return }
            self.installers = InstallerFiles.sorted(found)
                .map { InstallerFile(found: $0, ticked: InstallerFiles.tickedByDefault) }

            let caches = await Task.detached(priority: .utility) { Self.rawCaches() }.value
            guard !Task.isCancelled else { return }
            self.cacheOwners = Self.cacheOwners(from: caches, installed: installed)

            let trash = await Task.detached(priority: .utility) { Self.trashMeasurement() }.value
            guard !Task.isCancelled else { return }
            self.trashBytes = trash.bytes
            self.trashItems = trash.items

            let orphans = await Task.detached(priority: .utility) {
                Self.rawLeftovers(installed: installed)
            }.value
            guard !Task.isCancelled else { return }
            self.leftovers = orphans

            let heavy = await Task.detached(priority: .utility) { Self.rawHeavy() }.value
            guard !Task.isCancelled else { return }
            self.heavyData = Self.named(heavy, installed: installed)

            self.scanning = false
            self.state = self.cacheOwners.isEmpty ? .empty : .found
        }
    }

    /// Apps removed long ago whose data is still here. Found by asking the system
    /// which identifiers it knows and treating the rest as leftovers — with the
    /// guards that keep a helper of an installed app out of the list, and anything
    /// written to in the last month as well.
    nonisolated static func rawLeftovers(installed: Set<String>) -> [CacheOwner] {
        let manager = FileManager.default
        let home = NSHomeDirectory()
        let loaded = loadedLaunchdLabels()
        var found: [AppUninstall.LeftoverPath] = []

        for folder in AppUninstall.userFolders {
            let directory = "\(home)/Library/\(folder.name)"
            for entry in (try? manager.contentsOfDirectory(atPath: directory)) ?? [] {
                let base = AppUninstall.base(of: entry)
                // only identifier-shaped entries: a folder called "Notes" says
                // nothing about who owns it
                guard base.split(separator: ".").count >= 3, !base.contains(" ") else { continue }
                guard !AppUninstall.isSystemOwned(rawName: base) else { continue }
                let identifier = strippedTeamPrefix(base)
                guard AppUninstall.isLeftover(identifier: identifier,
                                              installedIdentifiers: installed) else { continue }
                // a job launchd is running right now has an owner, whatever the
                // folder dates say
                guard !AppUninstall.isLoadedByLaunchd(identifier: identifier,
                                                      loadedLabels: loaded) else { continue }
                let path = "\(directory)/\(entry)"
                let values = try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.contentModificationDateKey])
                let modified = values?.contentModificationDate ?? .distantPast
                // a group container and the plain folder of the same app are one
                // owner, so they are weighed and offered together
                found.append(AppUninstall.LeftoverPath(
                    identifier: AppUninstall.unwrapped(identifier), path: path,
                    bytes: Self.size(of: path), modified: modified))
            }
        }
        return AppUninstall.quietGroups(from: found).compactMap { group -> CacheOwner? in
            guard group.bytes > 1_000_000 else { return nil }
            // the caches section lists installed apps only, so nothing appears twice
            return CacheOwner(identifier: group.identifier, name: group.identifier, appPath: nil,
                              paths: group.paths, bytes: group.bytes, ticked: false)
        }
    }

    /// The job labels launchd is running for this user, read once per scan.
    nonisolated static func loadedLaunchdLabels() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return [] }
        // PID <tab> status <tab> label, under a header line
        return Set(out.split(separator: "\n").dropFirst().compactMap {
            $0.split(separator: "\t").last.map(String.init)
        })
    }

    /// The installed identifier that owns this one: itself, or the app it is a
    /// helper of (`com.foo.App` for `com.foo.App.Updater`).
    nonisolated static func owningApp(of identifier: String, installed: Set<String>) -> String? {
        // a group container names its app inside the wrapper, so the row can carry
        // the app's own name instead of a raw identifier
        let id = AppUninstall.unwrapped(identifier)
        if installed.contains(id) { return id }
        return installed.first { id.hasPrefix($0 + ".") }
    }

    /// Containers and group containers big enough to matter, which are NOT offered
    /// for clearing: cache and data live in one folder there. Telegram's is 23 GB
    /// with only an empty `Library/Caches` inside — the media sits in its own
    /// database, and only Telegram's own "clear cache" knows which of it is
    /// disposable (Anton asked why it was missing, 2026-07-30).
    nonisolated static func rawHeavy() -> [(path: String, identifier: String, bytes: Int64)] {
        let manager = FileManager.default
        let home = NSHomeDirectory()
        var out: [(path: String, identifier: String, bytes: Int64)] = []
        for folder in ["Containers", "Group Containers"] {
            let directory = "\(home)/Library/\(folder)"
            for entry in (try? manager.contentsOfDirectory(atPath: directory)) ?? [] {
                let path = "\(directory)/\(entry)"
                let identifier = strippedTeamPrefix(AppUninstall.base(of: entry))
                guard !AppUninstall.isSystemOwned(rawName: AppUninstall.base(of: entry))
                else { continue }
                let bytes = Self.size(of: path)
                guard bytes > 1_000_000_000 else { continue }   // a gigabyte or more
                out.append((path: path, identifier: identifier, bytes: bytes))
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    /// Puts an app's name on each of those folders. Split from the walk above
    /// because it asks LaunchServices, and LaunchServices is happier on the main
    /// thread than a size walk ever is.
    static func named(_ found: [(path: String, identifier: String, bytes: Int64)],
                      installed: Set<String>) -> [CacheOwner] {
        found.map { item in
            let owner = owningApp(of: item.identifier, installed: installed)
            let url = owner.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
            let name = url.map {
                FileManager.default.displayName(atPath: $0.path)
                    .replacingOccurrences(of: ".app", with: "")
            } ?? item.identifier
            return CacheOwner(identifier: item.path, name: name, appPath: url?.path,
                              paths: [item.path], bytes: item.bytes, ticked: false)
        }
    }

    /// Every identifier this Mac has an app for.
    nonisolated static func installedIdentifiers() -> [String] {
        let manager = FileManager.default
        var out: [String] = []
        for folder in ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "\(NSHomeDirectory())/Applications"] {
            for path in AppUninstall.appBundlePaths(inside: folder, manager: manager) {
                if let id = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier {
                    out.append(id)
                }
            }
        }
        return out
    }

    /// `<TEAMID>.<id>` → `<id>`: a team prefix is not part of the identifier.
    nonisolated static func strippedTeamPrefix(_ base: String) -> String {
        let parts = base.split(separator: ".").map(String.init)
        guard let first = parts.first, first.count == 10,
              first.uppercased() == first, !first.contains(where: \.isLowercase),
              parts.count > 2 else { return base }
        return parts.dropFirst().joined(separator: ".")
    }

    /// What the trash is holding, so the offer to empty it carries a number.
    nonisolated static func trashMeasurement() -> (bytes: Int64, items: Int) {
        let trash = "\(NSHomeDirectory())/.Trash"
        let items = ((try? FileManager.default.contentsOfDirectory(atPath: trash)) ?? [])
            .filter { !$0.hasPrefix(".") }.count
        return (bytes: size(of: trash), items: items)
    }

    /// Measures the trash again after emptying it, without redoing the rest.
    func measureTrash() {
        let measured = Self.trashMeasurement()
        trashBytes = measured.bytes
        trashItems = measured.items
    }

    /// Empties the trash through Finder, which is the only thing allowed to. The
    /// one irreversible action in the whole module, so the window asks first.
    func emptyTrash() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        measureTrash()
    }

    /// Every app that is holding a cache, biggest first. Built from the CACHE
    /// folders rather than from the list of apps: that way an identifier whose app
    /// is gone still shows up, labelled as a leftover.
    nonisolated static func rawCaches() -> [String: (paths: [String], bytes: Int64)] {
        let manager = FileManager.default
        let home = NSHomeDirectory()
        var byIdentifier: [String: (paths: [String], bytes: Int64)] = [:]

        func add(_ path: String, identifier: String) {
            var entry = byIdentifier[identifier] ?? ([], 0)
            entry.paths.append(path)
            entry.bytes += Self.size(of: path)
            byIdentifier[identifier] = entry
        }

        let caches = "\(home)/Library/Caches"
        for entry in (try? manager.contentsOfDirectory(atPath: caches)) ?? [] {
            // an identifier looks like one: at least two dots and no spaces
            guard entry.contains("."), !entry.hasPrefix("."),
                  !entry.contains(" ") else { continue }
            add("\(caches)/\(entry)", identifier: entry)
        }
        let containers = "\(home)/Library/Containers"
        for entry in (try? manager.contentsOfDirectory(atPath: containers)) ?? [] {
            let inner = AppUninstall.containerCache("\(containers)/\(entry)")
            guard manager.fileExists(atPath: inner) else { continue }
            add(inner, identifier: entry)
        }
        // A group container keeps its cache one level in — `<group>/Library/Caches`
        // and `<group>/<account>/Library/Caches` — so those count too.
        let groups = "\(home)/Library/Group Containers"
        for entry in (try? manager.contentsOfDirectory(atPath: groups)) ?? [] {
            let root = "\(groups)/\(entry)"
            var candidates = ["\(root)/Library/Caches"]
            for child in (try? manager.contentsOfDirectory(atPath: root)) ?? [] {
                candidates.append("\(root)/\(child)/Library/Caches")
            }
            for path in candidates where manager.fileExists(atPath: path) {
                guard Self.size(of: path) > 0 else { continue }
                add(path, identifier: entry)
            }
        }

        return byIdentifier
    }

    /// Turns the raw walk into the list the window shows: Apple's own caches out,
    /// noise out, leftovers out (they have a section of their own), and every
    /// remaining identifier named after the app that owns it.
    static func cacheOwners(from byIdentifier: [String: (paths: [String], bytes: Int64)],
                            installed: Set<String>) -> [CacheOwner] {
        byIdentifier.compactMap { identifier, entry -> CacheOwner? in
            // Apple's own caches are the system's business, not ours
            guard !AppUninstall.isSystemOwned(rawName: identifier) else { return nil }
            guard entry.bytes > 1_000_000 else { return nil }   // below a megabyte is noise
            // An app that IS installed but whose cache carries a helper's id —
            // `com.microsoft.VSCode.ShipIt` is the updater of an installed editor —
            // must be named after its owner, not called a leftover. Anything that
            // really has no owner belongs to the leftovers section instead, so it
            // is not listed twice (Anton, 2026-07-30).
            guard !AppUninstall.isLeftover(identifier: identifier,
                                           installedIdentifiers: installed) else { return nil }
            let owner = owningApp(of: identifier, installed: installed)
            let url = owner.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
            let name = url.map {
                FileManager.default.displayName(atPath: $0.path)
                    .replacingOccurrences(of: ".app", with: "")
            } ?? identifier
            return CacheOwner(identifier: identifier, name: name, appPath: url?.path,
                              paths: entry.paths, bytes: entry.bytes, ticked: false)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Moves a list of paths to the trash and writes the report. The one place
    /// that touches the disk for every list in the clean screen, so the promise —
    /// trash, never rm — cannot differ between them.
    private func trash(paths: [String]) {
        var trashed = 0
        var bytes: Int64 = 0
        var failed: [String] = []
        var protected: [String] = []
        for path in paths {
            let size = Self.size(of: path)
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path),
                                                 resultingItemURL: nil)
                trashed += 1
                bytes += size
            } catch {
                let code = (error as NSError).code
                if code == NSFileWriteNoPermissionError || code == NSFileReadNoPermissionError {
                    protected.append(path)
                } else {
                    failed.append(path)
                }
            }
        }
        report = Report(trashed: trashed, bytes: bytes, failed: failed, stayed: [],
                        needsFullDisk: protected)
        state = .done
    }

    /// Moves the ticked leftovers to the trash — everything of an app that is gone.
    func removeTickedLeftovers() {
        let chosen = leftovers.filter(\.ticked)
        trash(paths: chosen.flatMap(\.paths))
        leftovers.removeAll { owner in chosen.contains { $0.id == owner.id } }
    }

    /// Clears the caches of every ticked owner. Nothing else of theirs is touched.
    func clearTickedCaches() {
        let chosen = cacheOwners.filter(\.ticked)
        var trashed = 0
        var bytes: Int64 = 0
        var failed: [String] = []
        var protected: [String] = []
        for owner in chosen {
            for path in owner.paths {
                do {
                    try FileManager.default.trashItem(at: URL(fileURLWithPath: path),
                                                     resultingItemURL: nil)
                    trashed += 1
                    bytes += Self.size(of: path)
                } catch {
                    let code = (error as NSError).code
                    if code == NSFileWriteNoPermissionError || code == NSFileReadNoPermissionError {
                        protected.append(path)
                    } else {
                        failed.append(path)
                    }
                }
            }
        }
        report = Report(trashed: trashed, bytes: bytes, failed: failed, stayed: [],
                        needsFullDisk: protected)
        cacheOwners.removeAll { owner in chosen.contains { $0.id == owner.id } }
        state = .done
    }

    /// The apps on this Mac, so removing one is a click rather than a drag. Sizes
    /// are deliberately NOT computed here: walking /Applications takes seconds on a
    /// machine with a design suite installed, and the list is for choosing.
    /// Content for the product screenshots. A picture of an empty window says
    /// nothing about a module whose whole point is what it FINDS, and the real
    /// lists are this Mac's own — somebody's apps, somebody's disk. Only ever
    /// called from a snapshot render.
    func stageDemo(_ job: Mode) {
        mode = job
        report = nil
        scanning = false
        let generic = NSWorkspace.shared.icon(for: .application)
        switch job {
        case .uninstall:
            target = Target(path: "/Applications/Krita.app", name: "Krita",
                            bundleIdentifier: "org.krita.krita", icon: generic)
            let home = NSHomeDirectory()
            let staged: [(String, AppUninstall.Kind, Int64)] = [
                ("/Applications/Krita.app", .app, 612_000_000),
                ("\(home)/Library/Application Support/org.krita.krita", .support, 148_000_000),
                ("\(home)/Library/Caches/org.krita.krita", .caches, 96_000_000),
                ("\(home)/Library/Preferences/org.krita.krita.plist", .preferences, 24_000),
                ("\(home)/Library/Saved Application State/org.krita.krita.savedState", .savedState, 1_200_000),
                ("\(home)/Library/HTTPStorages/org.krita.krita", .httpStorages, 640_000),
                ("\(home)/Library/Logs/Krita", .logs, 4_800_000),
                ("\(home)/Library/LaunchAgents/org.krita.krita.plist", .launchAgent, 2_100),
            ]
            traces = staged.map {
                Trace(candidate: AppUninstall.Candidate(path: $0.0, kind: $0.1, match: .identifier),
                      bytes: $0.2, ticked: true)
            }
            state = .found
        case .clean:
            target = nil
            cacheOwners = [
                owner("org.mozilla.firefox", "Firefox", 3_400_000_000),
                owner("org.blenderfoundation.blender", "Blender", 1_240_000_000),
                owner("org.videolan.vlc", "VLC", 642_000_000),
                owner("org.inkscape.Inkscape", "Inkscape", 214_000_000),
                owner("com.obsproject.obs-studio", "OBS Studio", 88_000_000),
            ]
            leftovers = [
                CacheOwner(identifier: "org.gimp.gimp", name: "org.gimp.gimp", appPath: nil,
                           paths: [], bytes: 96_000_000, ticked: false),
                CacheOwner(identifier: "net.sourceforge.audacity", name: "net.sourceforge.audacity",
                           appPath: nil, paths: [], bytes: 42_000_000, ticked: false),
            ]
            installers = [
                InstallerFile(found: InstallerFiles.Found(
                    path: "\(NSHomeDirectory())/Downloads/blender-4.2-macos.dmg",
                    bytes: 384_000_000, modified: Date(timeIntervalSince1970: 1_780_000_000)),
                              ticked: false),
                InstallerFile(found: InstallerFiles.Found(
                    path: "\(NSHomeDirectory())/Downloads/obs-studio.pkg",
                    bytes: 212_000_000, modified: Date(timeIntervalSince1970: 1_776_000_000)),
                              ticked: false),
            ]
            heavyData = [
                CacheOwner(identifier: "heavy-1", name: "Telegram", appPath: "/Applications",
                           paths: [], bytes: 23_100_000_000, ticked: false),
            ]
            trashBytes = 4_260_000_000
            trashItems = 312
            state = .found
        }
    }

    private func owner(_ identifier: String, _ name: String, _ bytes: Int64) -> CacheOwner {
        CacheOwner(identifier: identifier, name: name, appPath: "/Applications/\(name).app",
                   paths: [], bytes: bytes, ticked: false)
    }

    func listInstalledApps() {
        let manager = FileManager.default
        let folders = ["/Applications", "\(NSHomeDirectory())/Applications"]
        var apps: [InstalledApp] = []
        for folder in folders {
            for entry in (try? manager.contentsOfDirectory(atPath: folder)) ?? []
            where entry.hasSuffix(".app") {
                let path = "\(folder)/\(entry)"
                let id = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier ?? ""
                apps.append(InstalledApp(
                    path: path,
                    name: manager.displayName(atPath: path)
                        .replacingOccurrences(of: ".app", with: ""),
                    identifier: id,
                    icon: NSWorkspace.shared.icon(forFile: path)))
            }
        }
        installedApps = Self.sorted(apps, by: appSort)
        state = installedApps.isEmpty ? .empty : .found
        weighInstalledApps()
    }

    static func sorted(_ apps: [InstalledApp], by order: AppSort) -> [InstalledApp] {
        switch order {
        case .name:
            return apps.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .size:
            // biggest first, and anything not weighed yet keeps its place at the
            // bottom rather than jumping around as the numbers arrive
            return apps.sorted { $0.totalBytes > $1.totalBytes }
        }
    }

    /// Weighs every app AFTER the list is on screen: /Applications with a design
    /// suite in it takes seconds to add up, and a list you cannot see yet is not
    /// worth waiting for. Each app lands as it is measured.
    private func weighInstalledApps() {
        appWeighing?.cancel()
        let apps = installedApps.map { (path: $0.path, id: $0.identifier, name: $0.name) }
        appWeighing = Task { [weak self] in
            for app in apps {
                let sizes = await Task.detached(priority: .utility) { () -> (Int64, Int64) in
                    let bundle = Self.size(of: app.path)
                    let traces = Self.scanTraces(identifier: app.id, name: app.name,
                                                 appPath: app.path)
                        .filter { $0.path != app.path }
                        .reduce(Int64(0)) { $0 + $1.bytes }
                    return (bundle, traces)
                }.value
                guard !Task.isCancelled, let self else { return }
                guard let index = self.installedApps.firstIndex(where: { $0.path == app.path })
                else { continue }
                self.installedApps[index].appBytes = sizes.0
                self.installedApps[index].traceBytes = sizes.1
            }
            guard !Task.isCancelled, let self else { return }
            self.installedApps = Self.sorted(self.installedApps, by: self.appSort)
        }
    }

    /// Installers sitting in the folders a download lands in. No app needed: this
    /// mode is about the .dmg nobody opened again.
    nonisolated static func rawInstallers() -> [InstallerFiles.Found] {
        let manager = FileManager.default
        let home = NSHomeDirectory()
        var found: [InstallerFiles.Found] = []
        for folder in InstallerFiles.folders {
            let directory = "\(home)/\(folder)"
            let entries = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
            for entry in entries where InstallerFiles.isInstaller(entry) {
                let path = "\(directory)/\(entry)"
                let values = try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.contentModificationDateKey])
                found.append(InstallerFiles.Found(
                    path: path, bytes: Self.size(of: path),
                    modified: values?.contentModificationDate ?? .distantPast))
            }
        }
        return found
    }

    /// Moves the ticked installers to the trash. Same promise as everywhere else.
    func removeTickedInstallers() {
        let chosen = installers.filter(\.ticked)
        var trashed = 0
        var bytes: Int64 = 0
        var failed: [String] = []
        for file in chosen {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: file.found.path),
                                                 resultingItemURL: nil)
                trashed += 1
                bytes += file.found.bytes
            } catch {
                failed.append(file.found.path)
            }
        }
        report = Report(trashed: trashed, bytes: bytes, failed: failed, stayed: [])
        installers.removeAll { file in chosen.contains { $0.id == file.id } }
        state = .done
    }

    /// Lists every known folder and keeps the entries that belong to this app.
    /// Listing rather than guessing exact paths is the whole point: an app leaves
    /// `Containers/<id>.<extension>`, `Group Containers/<team>.<id>` and
    /// `Caches/<id>.ShipIt`, none of which a guessed path finds.
    /// The identifier to work with: the bundle's own, or — when the app is already
    /// in the Trash — the one the Trash copy or the leftovers themselves imply.
    nonisolated static func resolvedIdentifier(provided: String, name: String) -> String {
        guard provided.isEmpty else { return provided }
        return trashedIdentifier(name: name) ?? inferredIdentifier(name: name) ?? ""
    }

    nonisolated static func scanTraces(identifier: String, name: String, appPath: String)
    -> [Trace] {
        let manager = FileManager.default
        // The app may already be in the Trash — that is what most people do first —
        // in which case there is no Info.plist to read and only name matches work.
        // Two ways back to the identifier: the bundle sitting in the Trash, and the
        // entries that spell the id out themselves.
        let identifier = resolvedIdentifier(provided: identifier, name: name)
        var found: [Trace] = []
        if manager.fileExists(atPath: appPath) {
            found.append(Trace(candidate: AppUninstall.Candidate(path: appPath, kind: .app,
                                                                match: .identifier),
                               bytes: size(of: appPath), ticked: true))
        }

        let places = AppUninstall.userFolders.map { ("\(NSHomeDirectory())/Library/\($0.name)", $0.kind) }
            + AppUninstall.systemFolders.map { ("/Library/\($0.name)", $0.kind) }
        for (directory, kind) in places {
            let entries = (try? manager.contentsOfDirectory(atPath: directory)) ?? []
            for entry in entries {
                guard let candidate = AppUninstall.candidate(
                    directory: directory, entry: entry, kind: kind,
                    identifier: identifier, appName: name) else { continue }
                found.append(Trace(candidate: candidate,
                                   bytes: size(of: candidate.path),
                                   ticked: candidate.ticked))
            }
        }
        // the bundle first, then the biggest: the eye goes to what matters
        return found.sorted {
            if $0.kind == .app { return true }
            if $1.kind == .app { return false }
            return $0.bytes > $1.bytes
        }
    }

    /// The identifier of a bundle with this name sitting in the Trash.
    private nonisolated static func trashedIdentifier(name: String) -> String? {
        let trash = "\(NSHomeDirectory())/.Trash/\(name).app"
        guard FileManager.default.fileExists(atPath: trash) else { return nil }
        return Bundle(url: URL(fileURLWithPath: trash))?.bundleIdentifier
    }

    /// The identifier the leftovers themselves imply: a preference file called
    /// `ru.keepcoder.Telegram.plist` names it out loud. Only used when every entry
    /// that says anything says the SAME thing.
    private nonisolated static func inferredIdentifier(name: String) -> String? {
        let manager = FileManager.default
        let home = NSHomeDirectory()
        var entries: [String] = []
        for folder in ["Preferences", "Containers", "Group Containers", "Application Scripts",
                       "Application Support", "Caches", "HTTPStorages", "WebKit"] {
            entries += (try? manager.contentsOfDirectory(atPath: "\(home)/Library/\(folder)")) ?? []
        }
        return AppUninstall.agreedIdentifier(entries: entries, appName: name)
    }

    /// Allocated size on disk, the number Finder shows. A folder is walked; a
    /// failure counts as zero rather than stopping the scan.
    nonisolated static func scanSize(of path: String) -> Int64 { size(of: path) }

    private nonisolated static func size(of path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
        while let child = enumerator?.nextObject() as? URL {
            let childValues = try? child.resourceValues(forKeys: keys)
            total += Int64(childValues?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Removing

    /// Quits the app, unloads its agents, then moves every ticked path to the
    /// trash. Nothing is deleted outright: the whole run stays reversible until
    /// the user empties the trash.
    func removeTicked() async {
        guard let target, state != .working else { return }
        state = .working
        blockedByRunning = false

        if !quitIfRunning(bundleIdentifier: target.bundleIdentifier) {
            blockedByRunning = true
            state = .found
            return
        }

        let chosen = traces.filter(\.ticked)
        for trace in chosen where trace.kind == .launchAgent || trace.kind == .systemLaunchAgent
            || trace.kind == .launchDaemon {
            bootout(trace)
        }

        var trashed = 0
        var bytes: Int64 = 0
        var failed: [String] = []
        var protected: [String] = []
        var admin: [String] = []

        for trace in chosen {
            if AppUninstall.needsAdmin(path: trace.path, kind: trace.kind) {
                admin.append(trace.path)
                continue
            }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: trace.path),
                                                 resultingItemURL: nil)
                trashed += 1
                bytes += trace.bytes
            } catch {
                Self.log.error("trash failed: \(trace.path, privacy: .public)")
                if (error as NSError).code == NSFileWriteNoPermissionError
                    || (error as NSError).code == NSFileReadNoPermissionError {
                    protected.append(trace.path)
                } else {
                    failed.append(trace.path)
                }
            }
        }

        // Everything that needs an administrator goes in ONE authorised step, and
        // still into the trash rather than to /dev/null.
        if !admin.isEmpty {
            if Self.moveWithAdmin(admin) {
                trashed += admin.count
                bytes += chosen.filter { admin.contains($0.path) }.reduce(0) { $0 + $1.bytes }
            } else {
                failed.append(contentsOf: admin)
            }
        }

        report = Report(trashed: trashed, bytes: bytes, failed: failed,
                        stayed: AppUninstall.Remainder.allCases,
                        needsFullDisk: protected)
        traces = []
        state = .done
    }

    /// True when the app is not running any more. A refusal is reported rather
    /// than forced: an app killed mid-write can leave a corrupt file behind, and
    /// the user may simply have unsaved work open.
    private func quitIfRunning(bundleIdentifier id: String) -> Bool {
        guard !id.isEmpty else { return true }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        // give it a moment; this is a UI action, and a second is imperceptible
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                return true
            }
            usleep(100_000)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    /// `launchctl bootout` before the plist moves — otherwise launchd notices the
    /// file is gone, and a still-loaded job can write it straight back.
    private func bootout(_ trace: Trace) {
        let directory = (trace.path as NSString).deletingLastPathComponent
        let label = (trace.name as NSString).deletingPathExtension
        let domain = AppUninstall.launchdDomain(forDirectory: directory, uid: getuid())
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["bootout", "\(domain)/\(label)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    /// One administrator prompt for every system-level path at once. `mv` into the
    /// user's trash, not `rm`: same promise as the rest of the run.
    ///
    /// NO path is ever interpolated into the AppleScript. The script text is a
    /// fixed literal that reads its arguments from `argv` and shell-quotes them
    /// with AppleScript's own `quoted form of`; the paths themselves travel as
    /// process arguments, and the list of files travels in a NUL-separated temp
    /// file that only `xargs -0` reads. Building that string by interpolation is a
    /// local privilege escalation waiting to happen: a folder in /Library whose
    /// name contains a quote would have closed the literal and run as root
    /// (flagged in review, 2026-07-30).
    private nonisolated static func moveWithAdmin(_ paths: [String]) -> Bool {
        // Defence in depth: this path only ever handles system locations, and
        // anything else has no business being here.
        let allowed = ["/Library/", "/var/db/receipts/", "/Users/Shared/"]
        let system = paths.filter { path in allowed.contains { path.hasPrefix($0) } }
        guard !system.isEmpty, system.count == paths.count else { return false }

        let temp = FileManager.default.temporaryDirectory
        let listURL = temp.appendingPathComponent("hop-uninstall-\(UUID().uuidString)")
        let scriptURL = temp.appendingPathComponent("hop-uninstall-\(UUID().uuidString).sh")
        defer {
            try? FileManager.default.removeItem(at: listURL)
            try? FileManager.default.removeItem(at: scriptURL)
        }
        let list = Data(system.joined(separator: "\0").utf8) + Data([0])
        let script = """
        #!/bin/bash
        trash="$1"
        list="$2"
        /usr/bin/xargs -0 -I{} /bin/mv -f {} "$trash/" < "$list"
        """
        guard (try? list.write(to: listURL, options: [.atomic])) != nil,
              (try? Data(script.utf8).write(to: scriptURL, options: [.atomic])) != nil
        else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: listURL.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                               ofItemAtPath: scriptURL.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = [
            "-e", "on run argv",
            "-e", """
            do shell script "/bin/bash " & quoted form of (item 1 of argv) \
                & " " & quoted form of (item 2 of argv) \
                & " " & quoted form of (item 3 of argv) with administrator privileges
            """,
            "-e", "end run",
            scriptURL.path,
            "\(NSHomeDirectory())/.Trash",
            listURL.path,
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return false
        }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
