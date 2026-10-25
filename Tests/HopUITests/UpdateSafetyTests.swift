import AppKit
import XCTest
import HopCore
@testable import Hop

@MainActor
final class UpdateSafetyTests: XCTestCase {
    func testDeferredStatusRenderedLinesInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let copy = L10n.t(.updDeferred, lang)
            let font = lang.isRTL ? NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
                                  : NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
            for width: CGFloat in [180, 240, 320] {
                let text = NSTextStorage(string: copy, attributes: [.font: font])
                let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: width, height: 1000))
                container.lineFragmentPadding = 0; layout.addTextContainer(container); text.addLayoutManager(layout)
                layout.ensureLayout(for: container)
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, range, _ in
                    let line = (copy as NSString).substring(with: layout.characterRange(forGlyphRange: range, actualGlyphRange: nil)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let words = line.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    XCTAssertFalse(L10n.shortWords(lang).contains(words.last ?? ""), "\(lang.rawValue): \(line)")
                    XCTAssertFalse(L10n.trailingWords(lang).contains(words.first ?? ""), "\(lang.rawValue): \(line)")
                }
            }
        }
    }
    private var release: UpdateChecker.ReleaseInfo {
        .init(version: "99.0", zipURL: URL(string: "invalid:no-network")!,
              signatureURL: URL(string: "invalid:no-network")!, critical: true)
    }
    func testManualCheckDefersKnownCriticalReleaseWhileBusy() async {
        let info = release
        let updater = UpdateChecker(findRelease: { info })
        updater.installationAllowed = { false }
        await updater.check(manual: true)
        XCTAssertEqual(updater.status, .deferred)
    }
    func testDirectOnboardingInstallCannotBypassBusyCheck() async {
        let updater = UpdateChecker()
        updater.installationAllowed = { false }
        await updater.install(release)
        XCTAssertEqual(updater.status, .deferred)
    }
    func testWorkStartedDuringManifestFetchIsCheckedAgain() async {
        let info = release
        var busy = false
        let updater = UpdateChecker(findRelease: { busy = true; await Task.yield(); return info })
        updater.installationAllowed = { !busy }
        await updater.check(manual: true)
        XCTAssertTrue(busy)
        XCTAssertEqual(updater.status, .deferred)
    }
    func testManualDeferredRequestSurvivesAutomaticUpdatesDisabled() async {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: UpdateChecker.autoUpdateKey)
        defer {
            if let previous { defaults.set(previous, forKey: UpdateChecker.autoUpdateKey) }
            else { defaults.removeObject(forKey: UpdateChecker.autoUpdateKey) }
        }
        defaults.set(false, forKey: UpdateChecker.autoUpdateKey)
        let updater = UpdateChecker()
        updater.installationAllowed = { false }
        await updater.install(release)
        await updater.installPendingIfPossible(canInstall: { _ in false })
        XCTAssertEqual(updater.pendingRelease?.info.version, "99.0")
        XCTAssertEqual(updater.pendingRelease?.manual, true)
        XCTAssertEqual(updater.status, .deferred)
    }
    func testTorrentRemovalAndSeedingPreventRelaunch() {
        XCTAssertTrue(TorrentController.blocksUpdate(adds: 0, removalsPending: true, torrents: []))
        XCTAssertTrue(TorrentController.blocksUpdate(adds: 1, removalsPending: false, torrents: []))
        func item(_ state: TorrentState, finished: Bool, uploading: Int64) -> TorrentController.TorrentItem {
            .init(id: "test", infoHash: "test", name: "test", files: [], outputFolder: "/unused",
                  stats: TorrentStats(state: state, progressBytes: 1, totalBytes: 1, uploadedBytes: 0,
                                      downloadBps: 0, uploadBps: uploading, peersLive: 0, peersSeen: 0,
                                      etaSeconds: nil, finished: finished, fileProgressBytes: []))
        }
        XCTAssertTrue(TorrentController.blocksUpdate(adds: 0, removalsPending: false,
            torrents: [item(.live, finished: true, uploading: 100)]))
        XCTAssertTrue(TorrentController.blocksUpdate(adds: 0, removalsPending: false,
            torrents: [item(.live, finished: false, uploading: 0)]))
        XCTAssertFalse(TorrentController.blocksUpdate(adds: 0, removalsPending: false,
            torrents: [item(.paused, finished: false, uploading: 0)]))
        XCTAssertFalse(TorrentController.blocksUpdate(adds: 0, removalsPending: false,
            torrents: [item(.live, finished: true, uploading: 0)]))
    }

    func testAutomaticInstallRechecksLiveIdlePolicy() async {
        let updater = UpdateChecker()
        updater.installationAllowed = { true }
        updater.automaticInstallationAllowed = { _ in false }
        await updater.install(release, manual: false)
        XCTAssertEqual(updater.status, .deferred)
        XCTAssertEqual(updater.pendingRelease?.manual, false)
    }

    func testNewManualCheckDropsWithdrawnPendingRelease() async {
        let info = release
        var found = true
        let updater = UpdateChecker(findRelease: { found ? info : nil })
        updater.installationAllowed = { false }
        await updater.check(manual: true)
        XCTAssertNotNil(updater.pendingRelease)
        found = false
        await updater.check(manual: true)
        XCTAssertNil(updater.pendingRelease)
        XCTAssertEqual(updater.status, .upToDate)
    }

    func testFailedRecheckKeepsKnownDeferredRelease() async {
        let info = release
        var fail = false
        let updater = UpdateChecker(findRelease: {
            if fail { throw URLError(.notConnectedToInternet) }
            return info
        })
        updater.installationAllowed = { false }
        await updater.check(manual: true)
        fail = true
        await updater.check(manual: true)
        XCTAssertEqual(updater.pendingRelease?.info.version, "99.0")
        XCTAssertEqual(updater.status, .deferred)
    }

}
