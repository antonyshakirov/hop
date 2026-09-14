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
            (stats(state: .initializing), true),
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

    private let stalled = TorrentStallWatch.Signal(stalled: true, flowing: false, checking: false)
    private let both = TorrentStallWatch.Signal(stalled: true, flowing: true, checking: false)
    private let flowing = TorrentStallWatch.Signal(stalled: false, flowing: true, checking: false)

    // MARK: - observe

    func testRestartsOnlyAfterTheStallLastsLongEnough() {
        var w = TorrentStallWatch()
        XCTAssertFalse(w.observe(stalled, now: at(0)))
        XCTAssertFalse(w.observe(stalled, now: at(TorrentStallWatch.stallAfter - 1)))
        XCTAssertTrue(w.observe(stalled, now: at(TorrentStallWatch.stallAfter)))
    }

    func testFlowResetsTheStallClock() {
        var w = TorrentStallWatch()
        _ = w.observe(stalled, now: at(0))
        _ = w.observe(both, now: at(100))
        XCTAssertFalse(w.observe(stalled, now: at(TorrentStallWatch.stallAfter + 1)))
    }

    func testRestartsAreSpacedApart() {
        var w = TorrentStallWatch()
        let s = TorrentStallWatch.stallAfter
        _ = w.observe(stalled, now: at(0))
        XCTAssertTrue(w.observe(stalled, now: at(s)))
        _ = w.observe(stalled, now: at(s + 1))
        XCTAssertFalse(w.observe(stalled, now: at(2 * s + 2)),
                       "a second restart must wait out the spacing")
        XCTAssertTrue(w.observe(stalled, now: at(s + TorrentStallWatch.spacing)))
    }

    /// Restarts that bring no traffic back mean the engine is not the problem.
    /// Each costs a full re-check of the payload, so the watch gives up.
    func testGivesUpAfterFruitlessRestarts() {
        var w = TorrentStallWatch()
        var now: TimeInterval = 0
        var restarts = 0
        for _ in 0..<(TorrentStallWatch.maxFruitlessRestarts + 3) {
            _ = w.observe(stalled, now: at(now))
            now += TorrentStallWatch.spacing
            if w.observe(stalled, now: at(now)) { restarts += 1 }
        }
        XCTAssertEqual(restarts, TorrentStallWatch.maxFruitlessRestarts)
    }

    func testFlowOrANewNetworkRearmsTheWatch() {
        for rearm in ["flow", "network"] {
            var w = TorrentStallWatch()
            var now: TimeInterval = 0
            for _ in 0..<TorrentStallWatch.maxFruitlessRestarts {
                _ = w.observe(stalled, now: at(now))
                now += TorrentStallWatch.spacing
                _ = w.observe(stalled, now: at(now))
            }
            if rearm == "flow" { _ = w.observe(flowing, now: at(now)) }
            else { w.pathUpdated(online: true, interfaces: ["en0"]); w.pathUpdated(online: true, interfaces: ["en1"]) }
            now += TorrentStallWatch.spacing
            _ = w.observe(stalled, now: at(now))
            now += TorrentStallWatch.stallAfter
            XCTAssertTrue(w.observe(stalled, now: at(now)), rearm)
        }
    }

    /// A re-check of a large payload can take longer than the stall threshold;
    /// restarting would throw its progress away and start hashing again.
    func testARecheckInProgressHoldsOffTheRestart() {
        let a = TorrentStallWatch.assess([(stats(), false), (stats(state: .initializing), false)])
        XCTAssertTrue(a.checking)
        var w = TorrentStallWatch()
        _ = w.observe(stalled, now: at(0))
        XCTAssertFalse(w.observe(a, now: at(TorrentStallWatch.stallAfter)))
        XCTAssertFalse(w.observe(stalled, now: at(TorrentStallWatch.stallAfter + 1)),
                       "the stall clock starts over once the re-check is done")
    }

    func testNoRestartWhileOffline() {
        var w = TorrentStallWatch()
        w.pathUpdated(online: true, interfaces: ["en0"])
        _ = w.observe(stalled, now: at(0))
        w.pathUpdated(online: false, interfaces: [])
        XCTAssertFalse(w.observe(stalled, now: at(TorrentStallWatch.stallAfter)))
        w.pathUpdated(online: true, interfaces: ["en0"])
        _ = w.observe(stalled, now: at(TorrentStallWatch.stallAfter + 1))
        XCTAssertFalse(w.observe(stalled, now: at(TorrentStallWatch.stallAfter + 2)),
                       "the stall is measured from when the network came back")
        XCTAssertTrue(w.observe(stalled, now: at(2 * TorrentStallWatch.stallAfter + 1)))
    }

    func testARestartThatNeverHappenedDoesNotCountAsFruitless() {
        var w = TorrentStallWatch()
        var now: TimeInterval = 0
        var restarts = 0
        for _ in 0..<(TorrentStallWatch.maxFruitlessRestarts + 2) {
            _ = w.observe(stalled, now: at(now))
            now += TorrentStallWatch.spacing
            if w.observe(stalled, now: at(now)) { restarts += 1; w.restartFailed() }
        }
        XCTAssertEqual(restarts, TorrentStallWatch.maxFruitlessRestarts + 2)
    }

    /// Path updates also arrive for VPN tunnels and cost flags on the same
    /// network; only a different set of interfaces or coming back online counts.
    func testOnlyARealNetworkChangeRearms() {
        func exhausted() -> (TorrentStallWatch, TimeInterval) {
            var w = TorrentStallWatch()
            w.pathUpdated(online: true, interfaces: ["en0"])
            var now: TimeInterval = 0
            for _ in 0..<TorrentStallWatch.maxFruitlessRestarts {
                _ = w.observe(stalled, now: at(now))
                now += TorrentStallWatch.spacing
                _ = w.observe(stalled, now: at(now))
            }
            return (w, now)
        }
        func restartsAfter(_ update: (inout TorrentStallWatch) -> Void) -> Bool {
            var (w, now) = exhausted()
            update(&w)
            now += TorrentStallWatch.spacing
            _ = w.observe(stalled, now: at(now))
            now += TorrentStallWatch.stallAfter
            return w.observe(stalled, now: at(now))
        }
        XCTAssertFalse(restartsAfter { $0.pathUpdated(online: true, interfaces: ["en0"]) })
        XCTAssertTrue(restartsAfter { $0.pathUpdated(online: true, interfaces: ["en1"]) })
        XCTAssertTrue(restartsAfter {
            $0.pathUpdated(online: false, interfaces: [])
            $0.pathUpdated(online: true, interfaces: ["en0"])
        })
    }
}
