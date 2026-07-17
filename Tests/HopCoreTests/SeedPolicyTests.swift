import XCTest
@testable import HopCore

final class SeedPolicyTests: XCTestCase {
    private func stats(finished: Bool, prog: Int64, up: Int64) -> TorrentStats {
        TorrentStats(state: .live, progressBytes: prog, totalBytes: prog, uploadedBytes: up,
                     downloadBps: 0, uploadBps: 0, peersLive: 1, peersSeen: 1,
                     etaSeconds: nil, finished: finished, fileProgressBytes: [prog])
    }
    func testPausesAtRatioOneWhenEnabled() {
        XCTAssertTrue(SeedPolicy.shouldPause(stats: stats(finished: true, prog: 100, up: 100), stopAtRatio1: true))
        XCTAssertTrue(SeedPolicy.shouldPause(stats: stats(finished: true, prog: 100, up: 101), stopAtRatio1: true))
    }
    func testKeepsSeedingBelowRatioOne() {
        XCTAssertFalse(SeedPolicy.shouldPause(stats: stats(finished: true, prog: 100, up: 99), stopAtRatio1: true))
    }
    func testNeverPausesWhenDisabled() {
        XCTAssertFalse(SeedPolicy.shouldPause(stats: stats(finished: true, prog: 100, up: 500), stopAtRatio1: false))
    }
    func testNeverPausesBeforeFinished() {
        XCTAssertFalse(SeedPolicy.shouldPause(stats: stats(finished: false, prog: 50, up: 100), stopAtRatio1: true))
    }
}
