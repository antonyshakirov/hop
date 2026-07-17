import XCTest
@testable import HopCore

final class TorrentModelTests: XCTestCase {
    func testFractionClampsAndComputes() {
        let s = TorrentStats(state: .live, progressBytes: 50, totalBytes: 100, uploadedBytes: 0,
                             downloadBps: 0, uploadBps: 0, peersLive: 0, peersSeen: 0,
                             etaSeconds: nil, finished: false, fileProgressBytes: [50])
        XCTAssertEqual(s.fraction, 0.5, accuracy: 0.0001)
    }
    func testFractionZeroWhenTotalUnknown() {
        let s = TorrentStats(state: .initializing, progressBytes: 0, totalBytes: 0, uploadedBytes: 0,
                             downloadBps: 0, uploadBps: 0, peersLive: 0, peersSeen: 0,
                             etaSeconds: nil, finished: false, fileProgressBytes: [])
        XCTAssertEqual(s.fraction, 0)
    }
    func testRatioUsesDownloadedAsDenominator() {
        let s = TorrentStats(state: .live, progressBytes: 200, totalBytes: 200, uploadedBytes: 100,
                             downloadBps: 0, uploadBps: 0, peersLive: 0, peersSeen: 0,
                             etaSeconds: nil, finished: true, fileProgressBytes: [200])
        XCTAssertEqual(s.ratio, 0.5, accuracy: 0.0001)
    }
}
