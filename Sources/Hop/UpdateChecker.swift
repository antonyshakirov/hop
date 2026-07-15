import AppKit
import CryptoKit
import Foundation

/// Updates via antonshakirov.com (latest.json + zip + signature):
/// silent auto-update and manual check. A release with critical=true
/// installs at the first opportunity.
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

    static let autoUpdateKey = "autoUpdateEnabled"

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
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor [weak self] in
                await self?.autoCheck(canInstall: canInstall)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The dev build stays offline: it updates via rebuilds, and a background
    /// request to the site would only trip testers' firewalls (LuLu etc.).
    static var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    private func autoCheck(canInstall: @MainActor (Bool) -> Bool) async {
        guard !Self.isDevBuild else { return }
        guard UserDefaults.standard.object(forKey: Self.autoUpdateKey) as? Bool ?? true
        else { return }
        guard let info = await fetchNewerRelease() else { return }
        guard canInstall(info.critical) else { return }
        await install(info)
    }

    /// A manual check downloads and installs any found update right away.
    func check(manual: Bool) async {
        guard status != .downloading, status != .installing else { return }
        status = .checking
        guard let info = await fetchNewerRelease() else {
            status = manual ? .upToDate : .idle
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

            // relaunch into the new version
            try run("/usr/bin/open", [target])
            NSApp.terminate(nil)
        } catch {
            status = .failed
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
