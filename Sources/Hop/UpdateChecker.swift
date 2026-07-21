import AppKit
import CryptoKit
import Foundation
import HopCore

/// Updates via antonshakirov.com (latest.json + zip + signature):
/// silent auto-update and manual check. The site is polled hourly; a found
/// release installs at the first idle moment (see UpdateInstallPolicy) rather
/// than waiting for the next poll — so it lands within a minute of the user
/// stepping away. A release with critical=true skips the idle wait.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Manifest of the latest release (scripts/release.sh uploads it to the site).
    static let feedURL = "https://www.antonshakirov.com/downloads/hop/latest.json"

    /// Ed25519 release signing key (scripts/sign-release.swift).
    /// Installation is possible ONLY with a valid signature by this key —
    /// even a site takeover cannot install a foreign build.
    static let updatePublicKeyBase64 = "UFJ6RcpmeswgKwn5WZB3twK4fDdlBHVOFCgdfxI7zec="

    struct ReleaseInfo {
        let version: String
        let zipURL: URL
        let signatureURL: URL
        let critical: Bool
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case downloading
        case installing
        case failed
    }

    @Published private(set) var status: Status = .idle
    private var statusExpiry: Task<Void, Never>?

    static let autoUpdateKey = "autoUpdateEnabled"

    /// How often the site is polled for a new release. Only the tiny latest.json
    /// is fetched; the zip downloads solely when a newer version is found.
    static let checkInterval: TimeInterval = 3600
    /// How often a release that was found but couldn't install yet re-tests the
    /// gate. No network — just the idle check — so a deferred update installs
    /// within a minute of the user going idle instead of at the next hourly poll.
    static let installRetryInterval: TimeInterval = 60

    /// A newer release found but not installable at that moment (timer running,
    /// panel open, recently used…). Kept so installPendingIfPossible can install
    /// it the instant the gate opens, without re-fetching.
    private var pendingRelease: ReleaseInfo?

    private var autoUpdateEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.autoUpdateKey) as? Bool ?? true
    }

    init() {
        Self.cleanupStagingLeftovers()
    }

    /// Installs stage the new bundle into temporaryDirectory/hop-update-<UUID>,
    /// and the dying process cannot delete its own staging after the copy — so
    /// every update left a ~7 MB folder behind (macOS only purges them days
    /// later). The next launch sweeps all of them instead.
    private static func cleanupStagingLeftovers() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let entries = try? fm.contentsOfDirectory(atPath: tmp.path) else { return }
        for name in entries where name.hasPrefix("hop-update-") {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    /// "latest version installed" is only true at the moment of the check:
    /// closing settings (or half an hour) clears it — an update may well
    /// have shipped since, and a stale note would keep denying it.
    func clearTransientStatus() {
        statusExpiry?.cancel()
        statusExpiry = nil
        if status == .upToDate || status == .failed { status = .idle }
    }

    private func scheduleStatusExpiry() {
        statusExpiry?.cancel()
        statusExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30 * 60))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.clearTransientStatus() }
        }
    }

    private var releaseKey: Curve25519.Signing.PublicKey? {
        guard let data = Data(base64Encoded: Self.updatePublicKeyBase64), !data.isEmpty
        else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: data)
    }

    var currentVersion: String {
        // the fallback covers bundle-less runs (snapshots, swift run) and leaks
        // into product screenshots — keep it the real version, not "dev";
        // stays in sync with scripts/Info.plist
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    // MARK: - Auto checks

    /// canInstall(critical) decides whether installing is OK right now: critical
    /// releases bypass the soft restrictions, but a running timer is never interrupted.
    func startAutoChecks(canInstall: @escaping @MainActor (_ critical: Bool) -> Bool) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            await self?.autoCheck(canInstall: canInstall)
        }
        let check = Timer(timeInterval: Self.checkInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.autoCheck(canInstall: canInstall)
            }
        }
        RunLoop.main.add(check, forMode: .common)
        // A release found while the user was busy installs the moment they go
        // idle, not a whole poll cycle later: this timer only re-tests the gate.
        let install = Timer(timeInterval: Self.installRetryInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.installPendingIfPossible(canInstall: canInstall)
            }
        }
        RunLoop.main.add(install, forMode: .common)
        // wake from sleep is a quiet moment too: the user is just coming
        // back and doesn't rely on the app yet — a found release installs
        // (and relaunches) before they notice. 30 s lets the network return
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                await self?.autoCheck(canInstall: canInstall)
            }
        }
    }

    /// The dev build stays offline: it updates via rebuilds, and a background
    /// request to the site would only trip testers' firewalls (LuLu etc.). Uses
    /// the shared "bundle id != production id" rule, so a bundle-less run (nil
    /// id) counts as dev and never auto-updates.
    static var isDevBuild: Bool { Bundle.isDevBuild }

    private func autoCheck(canInstall: @MainActor (Bool) -> Bool) async {
        guard !Self.isDevBuild, autoUpdateEnabled else { return }
        guard let info = await fetchNewerRelease() else {
            // nothing newer (or the release was pulled / already installed):
            // drop any stale pending so we don't keep trying to install it
            pendingRelease = nil
            return
        }
        await installOrDefer(info, canInstall: canInstall)
    }

    /// Install a found release now if the moment allows, otherwise remember it so
    /// the per-minute retry can install it the instant the user goes idle.
    private func installOrDefer(_ info: ReleaseInfo, canInstall: @MainActor (Bool) -> Bool) async {
        guard status != .downloading, status != .installing else { return }
        if canInstall(info.critical) {
            pendingRelease = nil
            await install(info)
        } else {
            pendingRelease = info
        }
    }

    /// Called every installRetryInterval: installs a previously found release the
    /// moment the gate opens (user went idle, stopped the timer, closed the panel).
    private func installPendingIfPossible(canInstall: @MainActor (Bool) -> Bool) async {
        guard let info = pendingRelease else { return }
        guard !Self.isDevBuild, autoUpdateEnabled else { pendingRelease = nil; return }
        guard status != .downloading, status != .installing else { return }
        guard canInstall(info.critical) else { return }
        // Clear before installing: a failed attempt then waits for the next
        // hourly check to rediscover, instead of hammering the download.
        pendingRelease = nil
        await install(info)
    }

    /// A manual check downloads and installs any found update right away.
    func check(manual: Bool) async {
        guard status != .downloading, status != .installing else { return }
        status = .checking
        guard let info = await fetchNewerRelease() else {
            status = manual ? .upToDate : .idle
            if status == .upToDate { scheduleStatusExpiry() }
            return
        }
        await install(info)
    }

    /// For onboarding: only find out whether an update exists (no install).
    func newerReleaseIfAny() async -> ReleaseInfo? {
        await fetchNewerRelease()
    }

    // MARK: - Mechanics

    private func fetchNewerRelease() async -> ReleaseInfo? {
        guard releaseKey != nil else { return nil } // updater is disabled without a key
        guard let url = URL(string: Self.feedURL) else { return nil }
        var request = URLRequest(url: url)
        // the manifest is tiny and must be fresh — bypass caches
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String,
              let zipURL = (json["zip"] as? String).flatMap(URL.init),
              // the signature is mandatory: a release without .sig is never installed
              let signatureURL = (json["sig"] as? String).flatMap(URL.init)
        else { return nil }

        guard Self.isNewer(version, than: currentVersion) else { return nil }
        return ReleaseInfo(
            version: version,
            zipURL: zipURL,
            signatureURL: signatureURL,
            critical: json["critical"] as? Bool ?? false
        )
    }

    func install(_ info: ReleaseInfo) async {
        do {
            status = .downloading
            let (tempZip, _) = try await URLSession.shared.download(from: info.zipURL)
            let (signature, _) = try await URLSession.shared.data(from: info.signatureURL)

            // cryptographic verification of the release with our key is
            // the only path to installation; a foreign build won't pass
            guard let key = releaseKey,
                  let zipData = try? Data(contentsOf: tempZip),
                  key.isValidSignature(signature, for: zipData)
            else {
                status = .failed
                scheduleStatusExpiry()
                return
            }

            status = .installing
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("hop-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            try run("/usr/bin/ditto", ["-xk", tempZip.path, staging.path])
            guard let appName = try FileManager.default.contentsOfDirectory(atPath: staging.path)
                .first(where: { $0.hasSuffix(".app") })
            else { throw URLError(.cannotParseResponse) }
            let newApp = staging.appendingPathComponent(appName)

            // quarantine is removed ONLY after the Ed25519 signature check above:
            // release authenticity is already proven by our key, and Gatekeeper
            // would simply block the ad-hoc build otherwise
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            let target = "/Applications/\(appName)"
            try? FileManager.default.removeItem(atPath: target)
            try FileManager.default.copyItem(atPath: newApp.path, toPath: target)

            // relaunch into the new version. A plain `open` here would only
            // activate the still-running old instance and nothing would start
            // the new one after terminate — so a detached shell waits for this
            // process to die and opens the fresh bundle afterwards
            let pid = ProcessInfo.processInfo.processIdentifier
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
            relauncher.arguments = ["-c",
                "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(target)\""]
            try relauncher.run() // deliberately not waited on — it must outlive us
            NSApp.terminate(nil)
        } catch {
            status = .failed
            scheduleStatusExpiry()
        }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Compare versions by numeric components: 1.2.10 > 1.2.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
