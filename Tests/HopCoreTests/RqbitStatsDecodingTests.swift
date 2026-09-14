import XCTest
@testable import HopCore

final class RqbitStatsDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testDecodesPopulatedStats() throws {
        let s = try RqbitDecoding.stats(from: fixture("rqbit-stats"))
        XCTAssertEqual(s.state, .live)
        XCTAssertEqual(s.totalBytes, 791674880)
        XCTAssertEqual(s.progressBytes, 144441344)
        XCTAssertEqual(s.fileProgressBytes, [144441344])
        XCTAssertEqual(s.uploadedBytes, 0)
        XCTAssertFalse(s.finished)
        XCTAssertEqual(s.peersLive, 104)
        XCTAssertEqual(s.peersSeen, 590)
        XCTAssertEqual(s.etaSeconds, 345)
        // 1.78485107421875 MiB/s * 1_048_576 ≈ 1.87 MB/s
        XCTAssertGreaterThan(s.downloadBps, 1_500_000)
        XCTAssertEqual(s.uploadBps, 0)
    }

    func testDecodesPausedStatsWithNullLive() throws {
        let s = try RqbitDecoding.stats(from: fixture("rqbit-stats-paused"))
        XCTAssertEqual(s.state, .paused)
        XCTAssertEqual(s.downloadBps, 0)
        XCTAssertEqual(s.uploadBps, 0)
        XCTAssertEqual(s.peersLive, 0)
        XCTAssertEqual(s.peersSeen, 0)
        XCTAssertNil(s.etaSeconds)
    }

    func testRqbit9LiveStatsDecode() throws {
        let s = try RqbitDecoding.stats(from: fixture("rqbit9-stats"))
        XCTAssertEqual(s.state, .live)
        XCTAssertEqual(s.progressBytes, 156838388)
        XCTAssertEqual(s.totalBytes, 9128454644)
        XCTAssertEqual(s.peersLive, 2)
        XCTAssertEqual(s.peersSeen, 97)
        XCTAssertEqual(s.etaSeconds, 5762)
        XCTAssertGreaterThan(s.downloadBps, 1_500_000)
        XCTAssertEqual(s.checkedBytes, 0)
    }

    func testRqbit9PausedStatsDecode() throws {
        let s = try RqbitDecoding.stats(from: fixture("rqbit9-stats-paused"))
        XCTAssertEqual(s.state, .paused)
        XCTAssertEqual(s.progressBytes, 156838388)
        XCTAssertEqual(s.peersLive, 0)
    }

    /// While a torrent is initializing rqbit reports how much of the payload it
    /// has hashed in `progress_bytes`, measured against the whole torrent. Read as
    /// downloaded bytes it once showed "27 GB" for a torrent 9% done.
    func testInitializingProgressIsCheckingNotDownloaded() throws {
        let s = try RqbitDecoding.stats(from: fixture("rqbit9-stats-initializing"))
        XCTAssertEqual(s.state, .initializing)
        XCTAssertEqual(s.progressBytes, 0)
        XCTAssertEqual(s.fraction, 0)
        XCTAssertEqual(s.checkedBytes, 27_000_000_000)
        XCTAssertEqual(s.checkingFraction, 0.9, accuracy: 0.0001)
    }
}
