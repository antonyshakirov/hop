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
}
