#if DEBUG
import Foundation
import HopCore

/// `Hop --torrent-removal-selftest <torrent> <payloadFolder>` walks the path that
/// brought a moved film back into Downloads (2026-09-17) against a real engine in
/// the bundle-less `.cli` storage: finish, move the file away, restart, switch the
/// module off, remove. The engine binary must already sit in that storage.
@MainActor
enum TorrentRemovalSelfTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--torrent-removal-selftest"), args.count > i + 2 else { return }
        let torrentPath = args[i + 1]
        let folder = URL(fileURLWithPath: args[i + 2], isDirectory: true)
        Task { @MainActor in
            do {
                try await run(torrent: URL(fileURLWithPath: torrentPath), folder: folder)
                print("SELFTEST OK")
                exit(0)
            } catch {
                print("SELFTEST FAIL: \(error)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }

    struct Failure: Error, CustomStringConvertible { let description: String }

    private static func check(_ ok: Bool, _ what: String) throws {
        print((ok ? "  ok   " : "  FAIL ") + what)
        if !ok { throw Failure(description: what) }
    }

    private static func waitFor(_ seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return await condition()
    }

    private static func run(torrent: URL, folder: URL) async throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.storageIdentifier, isDirectory: true)
        let session = support.appendingPathComponent("torrent-session", isDirectory: true)

        let first = TorrentController()
        let pending = try await first.fetchFiles(source: .file(try Data(contentsOf: torrent)))
        try await first.confirmAdd(pending, selectedIndices: Set(pending.files.map(\.index)), outputFolder: folder)
        let payload = folder.appendingPathComponent(pending.files[0].name)
        try await check(waitFor(30) {
            await first.pollOnce()
            return first.torrents.first?.stats?.finished == true
        }, "a torrent whose file is on disk finishes and seeds")

        let moved = folder.appendingPathComponent("moved-away.bin")
        try FileManager.default.moveItem(at: payload, to: moved)
        try await check(waitFor(10) {
            await first.pollOnce()
            return first.torrents.first?.filesMissing == true
        }, "moving the file of a SEEDING torrent flags the row")
        try await check(waitFor(10) {
            await first.pollOnce()
            return first.torrents.first?.stats?.state == .paused
        }, "and pauses the torrent")
        first.stopEngine()

        let second = TorrentController()
        await second.restore()
        try check(second.torrents.first?.filesMissing == true, "after a restart the row still says the files are gone")
        await second.pollOnce()
        try check(second.torrents.first?.stats?.state == .paused, "and the engine does not download it again")

        // The module switched off: the engine is stopped with the row still on screen.
        second.stopEngine()
        let id = try second.torrents.first.map(\.id) ?? { throw Failure(description: "no row") }()
        second.remove(id: id, deleteFiles: false)
        try await check(waitFor(20) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: session.path)) ?? []
            return !files.contains { $0.hasSuffix(".torrent") }
        }, "✕ with the engine stopped still removes the torrent from the engine session")
        let removalsFile = support.appendingPathComponent("torrent-removals.json")
        try await check(waitFor(5) {
            let data = (try? Data(contentsOf: removalsFile)) ?? Data()
            return (try? JSONDecoder().decode(TorrentRemovals.self, from: data))?.isEmpty == true
        }, "the removal is settled")
        try await check(waitFor(5) { !FileManager.default.fileExists(atPath: payload.path) },
                        "the empty file the engine put back is gone")
        try check(FileManager.default.fileExists(atPath: moved.path), "the moved file is untouched")

        let third = TorrentController()
        await third.restore()
        try check(third.torrents.isEmpty, "the next launch shows no torrent")
        try check(!FileManager.default.fileExists(atPath: payload.path), "and nothing reappears in the folder")
        third.stopEngine()
    }
}
#endif
