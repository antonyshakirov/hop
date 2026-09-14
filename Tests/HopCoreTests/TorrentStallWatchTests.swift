import XCTest
@testable import HopCore

final class TorrentStallWatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func stats(state: TorrentState = .live, finished: Bool = false,
                       peers: Int = 0, down: Int64 = 0, up: Int64 = 0) -> TorrentStats {
        TorrentStats(state: state, progressBytes: 10, totalBytes: 100, uploadedBytes: 0,
                     downloadBps: down, uploadBps: up, peersLive: peers, peersSeen: 0,
                     etaSeconds: nil, finished: finished, fileProgressBytes: [10])
    }

    // MARK: - assess

    func testLiveUnfinishedWithoutPeersIsStalled() {
        let a = TorrentStallWatch.assess([(stats(), false)])
        XCTAssertTrue(a.stalled)
        XCTAssertFalse(a.flowing)
    }

    func testPausedFinishedInitializingAndUnknownRowsAreNotStalled() {
        let a = TorrentStallWatch.assess([
            (stats(), true),
            (stats(finished: true), false),
            (stats(state: .initializing), false),
            (stats(state: .paused), false),
            (nil, false),
        ])
        XCTAssertFalse(a.stalled)
        XCTAssertFalse(a.flowing)
    }

    /// A seeding torrent with a live peer proves the engine can reach the network;
    /// the stuck download is then a swarm problem a restart would not fix.
    func testAnyLivePeerOrTrafficCountsAsFlowing() {
        XCTAssertTrue(TorrentStallWatch.assess([(stats(peers: 1), false)]).flowing)
        XCTAssertTrue(TorrentStallWatch.assess([(stats(down: 5), false)]).flowing)
        XCTAssertTrue(TorrentStallWatch.assess([(stats(finished: true, up: 5), false)]).flowing)
        XCTAssertFalse(TorrentStallWatch.assess([(stats(peers: 3), true)]).flowing,
                       "a paused row's leftover numbers say nothing about the engine")
    }

    // MARK: - observe

    func testRestartsOnlyAfterTheStallLastsLongEnough() {
        var w = TorrentStallWatch()
        XCTAssertFalse(w.observe(stalled: true, flowing: false, now: at(0)))
        XCTAssertFalse(w.observe(stalled: true, flowing: false, now: at(TorrentStallWatch.stallAfter - 1)))
        XCTAssertTrue(w.observe(stalled: true, flowing: false, now: at(TorrentStallWatch.stallAfter)))
    }

    func testFlowResetsTheStallClock() {
        var w = TorrentStallWatch()
        _ = w.observe(stalled: true, flowing: false, now: at(0))
        _ = w.observe(stalled: true, flowing: true, now: at(100))
        XCTAssertFalse(w.observe(stalled: true, flowing: false, now: at(TorrentStallWatch.stallAfter + 1)))
    }

    func testRestartsAreSpacedApart() {
        var w = TorrentStallWatch()
        let s = TorrentStallWatch.stallAfter
        _ = w.observe(stalled: true, flowing: false, now: at(0))
        XCTAssertTrue(w.observe(stalled: true, flowing: false, now: at(s)))
        _ = w.observe(stalled: true, flowing: false, now: at(s + 1))
        XCTAssertFalse(w.observe(stalled: true, flowing: false, now: at(2 * s + 2)),
                       "a second restart must wait out the spacing")
        XCTAssertTrue(w.observe(stalled: true, flowing: false, now: at(s + TorrentStallWatch.spacing)))
    }

    /// Restarts that bring no traffic back mean the engine is not the problem.
    /// Each costs a full re-check of the payload, so the watch gives up.
    func testGivesUpAfterFruitlessRestarts() {
        var w = TorrentStallWatch()
        var now: TimeInterval = 0
        var restarts = 0
        for _ in 0..<(TorrentStallWatch.maxFruitlessRestarts + 3) {
            _ = w.observe(stalled: true, flowing: false, now: at(now))
            now += TorrentStallWatch.spacing
            if w.observe(stalled: true, flowing: false, now: at(now)) { restarts += 1 }
        }
        XCTAssertEqual(restarts, TorrentStallWatch.maxFruitlessRestarts)
    }

    func testFlowOrANewNetworkRearmsTheWatch() {
        for rearm in ["flow", "network"] {
            var w = TorrentStallWatch()
            var now: TimeInterval = 0
            for _ in 0..<TorrentStallWatch.maxFruitlessRestarts {
                _ = w.observe(stalled: true, flowing: false, now: at(now))
                now += TorrentStallWatch.spacing
                _ = w.observe(stalled: true, flowing: false, now: at(now))
            }
            if rearm == "flow" { _ = w.observe(stalled: false, flowing: true, now: at(now)) }
            else { w.networkChanged() }
            now += TorrentStallWatch.spacing
            _ = w.observe(stalled: true, flowing: false, now: at(now))
            now += TorrentStallWatch.stallAfter
            XCTAssertTrue(w.observe(stalled: true, flowing: false, now: at(now)), rearm)
        }
    }
}
