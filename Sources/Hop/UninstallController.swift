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
    }

    enum State: Equatable {
        case empty
        case scanning
        case found
        case working
        case done
    }

    @Published private(set) var state: State = .empty
    @Published private(set) var target: Target?
    @Published var traces: [Trace] = []
    @Published private(set) var report: Report?
    /// Set when the app refuses to quit — removing a running app leaves half of it
    /// behind and relaunches the rest.
    @Published private(set) var blockedByRunning = false

    var totalBytes: Int64 { traces.filter(\.ticked).reduce(0) { $0 + $1.bytes } }
    var needsAdmin: Bool { traces.contains { $0.ticked && $0.kind.needsAdmin } }

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
        traces = found
        state = traces.isEmpty ? .empty : .found
    }

    /// Lists every known folder and keeps the entries that belong to this app.
    /// Listing rather than guessing exact paths is the whole point: an app leaves
    /// `Containers/<id>.<extension>`, `Group Containers/<team>.<id>` and
    /// `Caches/<id>.ShipIt`, none of which a guessed path finds.
    nonisolated static func scanTraces(identifier: String, name: String, appPath: String)
    -> [Trace] {
        let manager = FileManager.default
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
        var admin: [String] = []

        for trace in chosen {
            if trace.kind.needsAdmin {
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
                failed.append(trace.path)
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
                        stayed: AppUninstall.Remainder.allCases)
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
