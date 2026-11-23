import HopHardwareKit
import XCTest
@testable import Hop

// SPEC: docs/spec.md — Lid and Awake are independent; the background heartbeat.
@MainActor
final class AwakeBackgroundTests: XCTestCase {
    private func countingGuard() -> (AppNapGuard, () -> (Int, Int)) {
        var begun = 0, ended = 0
        let napGuard = AppNapGuard(reason: "test", begin: { begun += 1; return NSObject() },
                                   end: { _ in ended += 1 })
        return (napGuard, { (begun, ended) })
    }

    func testTheGuardBeginsAndEndsOneActivityPerTransition() {
        let (napGuard, counts) = countingGuard()
        napGuard.hold(true); napGuard.hold(true)
        XCTAssertTrue(napGuard.isHeld)
        napGuard.hold(false); napGuard.hold(false)
        XCTAssertFalse(napGuard.isHeld)
        XCTAssertTrue(counts() == (1, 1))
    }

    func testAwakeHoldsTheGuardWhileOnAndReleasesItWhenTurnedOff() {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        let (napGuard, counts) = countingGuard()
        let awake = KeepAwakeController(demo: true, napGuard: napGuard)
        XCTAssertTrue(napGuard.isHeld)
        awake.deactivate(silent: true)
        XCTAssertFalse(napGuard.isHeld)
        XCTAssertTrue(counts() == (1, 1))
    }

    func testLidAloneHoldsTheGuard() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        let (napGuard, _) = countingGuard()
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in on }, napGuard: napGuard)
        awake.deactivate(silent: true)
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertTrue(awake.lidApplied)
        XCTAssertTrue(napGuard.isHeld)
        awake.lidServiceStopped()
        XCTAssertFalse(napGuard.isHeld)
    }

    func testTheServiceEndingTheLidLeavesAwakeRunning() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in on })
        let deadline = awake.until
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertTrue(awake.lidApplied)
        awake.lidServiceStopped()
        XCTAssertFalse(awake.lidApplied)
        XCTAssertTrue(awake.isActive)
        XCTAssertEqual(awake.until, deadline)
    }
}
