import XCTest
@testable import HopCore

/// A finished torrent once posted a banner carrying the timer's words, because
/// the body was left unset and the notification helper filled it with its own
/// default. These tests pin the message to the torrent's actual state.
final class TorrentBannerTests: XCTestCase {

    private func stats(
        progress: Int64 = 2_400_000_000,
        total: Int64 = 2_400_000_000,
        uploaded: Int64 = 1_200_000_000,
        finished: Bool = true
    ) -> TorrentStats {
        TorrentStats(
            state: .live, progressBytes: progress, totalBytes: total,
            uploadedBytes: uploaded, downloadBps: 0, uploadBps: 0,
            peersLive: 3, peersSeen: 12, etaSeconds: nil, finished: finished,
            fileProgressBytes: [])
    }

    func testFinishedWhileSharingPromisesSharing() {
        XCTAssertEqual(
            TorrentBanner.finished(stats: stats(), seeding: true),
            .downloadedSeeding(bytes: 2_400_000_000))
    }

    func testFinishedWhilePausedPromisesNothing() {
        XCTAssertEqual(
            TorrentBanner.finished(stats: stats(), seeding: false),
            .downloaded(bytes: 2_400_000_000))
    }

    /// With only some files selected the nominal total overstates what landed on
    /// disk. The banner has to quote the number the user can find in Finder.
    func testSizeIsWhatLandedNotTheNominalTotal() {
        let partial = stats(progress: 800_000_000, total: 2_400_000_000)
        XCTAssertEqual(
            TorrentBanner.finished(stats: partial, seeding: true).bytes,
            800_000_000)
    }

    func testSeedingStoppedQuotesWhatWasGivenBack() {
        let banner = TorrentBanner.seedingStopped(stats: stats(uploaded: 3_100_000_000))
        XCTAssertEqual(banner, .seedingFinished(uploadedBytes: 3_100_000_000))
        XCTAssertEqual(banner.bytes, 3_100_000_000)
    }

    /// Three distinct events, three distinct messages: no state may collapse
    /// into another's wording.
    func testEveryEventHasItsOwnMessage() {
        let all: [TorrentBanner] = [
            .finished(stats: stats(), seeding: true),
            .finished(stats: stats(), seeding: false),
            .seedingStopped(stats: stats()),
        ]
        XCTAssertEqual(Set(all.map(String.init(describing:))).count, 3)
    }
}
