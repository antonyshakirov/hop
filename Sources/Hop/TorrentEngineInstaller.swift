import Foundation
import HopCore

/// Downloads the rqbit torrent engine on demand and installs it into
/// Application Support — but only after an Ed25519 signature by our key proves
/// it authentic (a foreign binary never installs). Mirrors UpdateChecker.
///
/// Installation is possible ONLY with a valid Ed25519 signature by this key —
/// even a site takeover cannot install a foreign engine binary. An empty key
/// disables the installer entirely (fails closed), like the updater without its key.
@MainActor
final class TorrentEngineInstaller: ObservableObject {
    static let manifestURL = "https://www.antonshakirov.com/downloads/hop/engine/engine.json"
    /// Engine signing key (private half at ~/.minimo-torrent-engine-key, never committed).
    static let enginePublicKeyBase64 = "Kj8vty1B6wUQW33V6Rbb1774Oq0c2nmMmsUZP/HVzqE="

    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        case verifying
        case installed(URL)
        case failed
    }

    @Published private(set) var state: State = .notInstalled
    /// Engine download size from the manifest, so the view can reassure the user
    /// how small the fetch is (e.g. "~25 MB"). 0 until the manifest is decoded.
    @Published private(set) var engineSizeBytes: Int64 = 0

    init() {
        // Dev snapshots stage the installed (empty drop-zone) state so the
        // design renders without the engine actually being present on disk.
        if Snapshot.active { state = .installed(binaryURL) }
        else if installedBinaryURL() != nil { state = .installed(binaryURL) }
    }

    private var installDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.storageIdentifier
        return base.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("torrent-engine", isDirectory: true)
    }

    var binaryURL: URL { installDir.appendingPathComponent("rqbit") }

    func installedBinaryURL() -> URL? {
        FileManager.default.isExecutableFile(atPath: binaryURL.path) ? binaryURL : nil
    }

    /// Download, verify, install. Fails closed on any error or a missing key.
    func install() async {
        guard !Self.enginePublicKeyBase64.isEmpty, let manifestURL = URL(string: Self.manifestURL) else {
            state = .failed; return
        }
        do {
            state = .downloading(0)
            let (manifestData, _) = try await URLSession.shared.data(from: manifestURL)
            let manifest = try JSONDecoder().decode(EngineManifest.self, from: manifestData)
            // Require https on both URLs: a tampered manifest must not coerce a
            // file:// read or a plaintext-http fetch. (The Ed25519 gate still prevents
            // installing a foreign binary; this closes the scheme-downgrade angle.)
            guard let binURL = URL(string: manifest.url), binURL.scheme == "https",
                  let sigURL = URL(string: manifest.sig), sigURL.scheme == "https" else {
                state = .failed; return
            }
            // Expose the size for the view's "~25 MB" hint.
            engineSizeBytes = manifest.size ?? 0
            let tmpBin = try await downloadWithProgress(from: binURL)
            let (signature, _) = try await URLSession.shared.data(from: sigURL)

            state = .verifying
            guard let binData = try? Data(contentsOf: tmpBin),
                  EngineSignature.isValid(signature: signature, for: binData,
                                          publicKeyBase64: Self.enginePublicKeyBase64)
            else { state = .failed; return }

            try installVerified(from: tmpBin)
            state = .installed(binaryURL)
        } catch {
            state = .failed
        }
    }

    /// Copy the verified binary into place, clear quarantine (authenticity is
    /// already proven by our key — Gatekeeper would otherwise block an ad-hoc
    /// binary), and mark it executable.
    private func installVerified(from tmp: URL) throws {
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: binaryURL)
        try FileManager.default.copyItem(at: tmp, to: binaryURL)
        _ = try? runTool("/usr/bin/xattr", ["-d", "com.apple.quarantine", binaryURL.path])
        _ = try? runTool("/bin/chmod", ["+x", binaryURL.path])
    }

    @discardableResult
    private func runTool(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Download with a REAL progress readout. The async `download(from:)` API
    /// does not deliver per-chunk progress to a delegate, so we drive a
    /// downloadTask and observe its `progress.fractionCompleted` via KVO. The
    /// completion handler's temp file is deleted on return, so we move it out first.
    private func downloadWithProgress(from url: URL) async throws -> URL {
        let session = URLSession(configuration: .default)
        return try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            let task = session.downloadTask(with: url) { tmp, _, error in
                observation?.invalidate()
                observation = nil
                session.finishTasksAndInvalidate()
                if let error { continuation.resume(throwing: error); return }
                guard let tmp else { continuation.resume(throwing: URLError(.badServerResponse)); return }
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("hop-engine-\(UUID().uuidString)")
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in self?.state = .downloading(fraction) }
            }
            task.resume()
        }
    }
}
