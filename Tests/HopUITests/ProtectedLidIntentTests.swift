import HopHardwareKit
import XCTest
@testable import Hop

@MainActor
final class ProtectedLidIntentTests: XCTestCase {
    func testAnEnableCancelledBeforeItsTaskStartsNeverCallsTheService() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        var calls: [Bool] = []
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in calls.append(on); return on })
        awake.deactivate(silent: true)
        awake.toggleLid(); awake.toggleLid()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(calls, [false])
        XCTAssertFalse(awake.lidApplied)
        XCTAssertFalse(awake.lidChanging)
    }

    func testPendingOffKeepsActualStateSeparateAndCanBeReversed() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        var calls: [Bool] = []
        var off: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in
            calls.append(on)
            if !on { return try await withCheckedThrowingContinuation { off = $0 } }
            return true
        })
        awake.deactivate(silent: true)
        awake.toggleLid()
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertTrue(awake.lidApplied)
        awake.toggleLid()
        XCTAssertEqual(awake.pendingLidTarget, false)
        XCTAssertTrue(awake.lidApplied)
        for _ in 0..<100 where off == nil { await Task.yield() }
        awake.toggleLid()
        XCTAssertEqual(awake.pendingLidTarget, true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        off?.resume(returning: false)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(calls, [true, false, true])
        XCTAssertTrue(awake.lidApplied)
        XCTAssertNil(awake.pendingLidTarget)
    }

    func testASecondToggleCancelsAnEnableStillWaitingForTheService() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        var calls: [Bool] = []
        var gate: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in
            calls.append(on)
            if on { return try await withCheckedThrowingContinuation { gate = $0 } }
            return false
        })
        awake.deactivate(silent: true)
        awake.toggleLid()
        for _ in 0..<100 where gate == nil { await Task.yield() }
        XCTAssertNotNil(gate)
        awake.toggleLid()
        for _ in 0..<100 where calls.count < 2 { await Task.yield() }
        XCTAssertEqual(calls, [true, false])
        gate?.resume(returning: true)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(awake.lidApplied)
        XCTAssertFalse(awake.lidChanging)
    }

    func testEnablingLidAloneDoesNotChooseInfinityOrAcquireAwake() async {
        let saved = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = saved }
        var deadlines: [Date?] = []
        let awake = KeepAwakeController(demo: true, protectedLid: { on, until in deadlines.append(until); return on })
        awake.deactivate(silent: true)
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertTrue(awake.lidApplied)
        XCTAssertFalse(awake.isActive)
        XCTAssertNil(awake.selected)
        XCTAssertNil(awake.until)
        XCTAssertEqual(deadlines.count, 1)
        XCTAssertNil(deadlines.first!)
        awake.setLidEnabled(false)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
    }

    func testTurningAwakeOffDoesNotDisableTheLidLease() async {
        let saved = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = saved }
        var calls: [Bool] = []
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in calls.append(on); return on })
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        awake.deactivate()
        for _ in 0..<30 { await Task.yield() }
        XCTAssertFalse(awake.isActive)
        XCTAssertTrue(awake.lidApplied)
        XCTAssertEqual(calls, [true])
        awake.releaseLidForShutdown()
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertFalse(awake.lidApplied)
    }

    func testModuleOffReleasesActiveAndPendingLidWithoutLateRearm() async {
        let saved = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = saved }
        for pending in [false, true] {
            var reply: CheckedContinuation<Bool, Error>?
            var calls: [Bool] = []
            let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in
                calls.append(on)
                if on && pending { return try await withCheckedThrowingContinuation { reply = $0 } }
                return on
            })
            awake.deactivate(silent: true)
            awake.setLidEnabled(true)
            for _ in 0..<100 where pending ? reply == nil : awake.lidChanging { await Task.yield() }
            XCTAssertTrue(awake.hasModuleWork)
            awake.stopForModuleOff()
            for _ in 0..<100 where awake.lidChanging { await Task.yield() }
            reply?.resume(returning: true)
            for _ in 0..<30 { await Task.yield() }
            XCTAssertEqual(calls, [true, false])
            XCTAssertFalse(awake.hasModuleWork)
            XCTAssertFalse(awake.isActive)
            XCTAssertFalse(awake.lidApplied)
        }
    }

    func testOffDuringPendingEnableCannotBeUndoneByItsLateReply() async {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        var calls: [Bool] = []
        var reply: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in
            calls.append(on)
            if on { return try await withCheckedThrowingContinuation { reply = $0 } }
            return false
        })
        awake.setLidEnabled(true)
        for _ in 0..<100 where reply == nil { await Task.yield() }
        XCTAssertTrue(awake.lidChanging)
        awake.setLidEnabled(false)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertEqual(calls, [true, false])
        XCTAssertFalse(awake.lidApplied)
        reply?.resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(awake.lidApplied)
        XCTAssertFalse(awake.lidChanging)
    }

    func testChangingDurationDuringPendingLidEnableKeepsIndependentLease() async {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        var deadlines: [Date?] = []
        var firstReply: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { on, until in
            guard on else { return false }
            deadlines.append(until)
            if deadlines.count == 1 { return try await withCheckedThrowingContinuation { firstReply = $0 } }
            return true
        })
        defer { awake.deactivate(silent: true) }
        awake.activate(.init(label: "15", seconds: 900))
        XCTAssertTrue(awake.isActive)
        awake.setLidEnabled(true)
        for _ in 0..<100 where firstReply == nil { await Task.yield() }
        XCTAssertNotNil(firstReply)
        awake.activate(.init(label: "2h", seconds: 7200))
        firstReply?.resume(returning: true)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(deadlines.count, 1)
        XCTAssertNil(deadlines.first!)
        XCTAssertTrue(awake.lidApplied)
    }

    func testDurationChangeDoesNotReenableLidWhileOffReplyIsPending() async {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        var calls: [Bool] = []
        var offReply: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in
            calls.append(on)
            if !on { return try await withCheckedThrowingContinuation { offReply = $0 } }
            return true
        })
        defer { awake.deactivate(silent: true) }
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertTrue(awake.lidApplied)
        awake.setLidEnabled(false)
        for _ in 0..<100 where offReply == nil { await Task.yield() }
        XCTAssertNotNil(offReply)
        awake.activate(.init(label: "2h", seconds: 7200))
        offReply?.resume(returning: false)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(calls, [true, false])
        XCTAssertFalse(awake.lidApplied)
        XCTAssertFalse(awake.lidChanging)
    }

    func testDurationChangeDoesNotRetryAFailedLidEnable() async {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        var calls = 0
        let awake = KeepAwakeController(demo: true, protectedLid: { _, _ in
            calls += 1
            throw HardwareReason.commandFailed
        })
        defer { awake.deactivate(silent: true) }
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(awake.lidFailure, .commandFailed)
        awake.activate(.init(label: "2h", seconds: 7200))
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(awake.lidApplied)
        XCTAssertEqual(awake.lidFailure, .commandFailed)
    }

    func testOffWhenAlreadyOffDoesNotStartAnAwakeSessionOrContactService() async {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        var calls = 0
        let awake = KeepAwakeController(demo: true, protectedLid: { _, _ in calls += 1; return false })
        awake.deactivate(silent: true)
        awake.setLidEnabled(false)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(awake.isActive)
        XCTAssertEqual(calls, 0)
    }

    func testFailedEnableReportsContextualReasonAndSuccessfulRetryClearsIt() async {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        var fail = true
        let awake = KeepAwakeController(demo: true, protectedLid: { _, _ in
            if fail { throw HardwareReason.busy }
            return true
        })
        defer { awake.deactivate(silent: true) }
        let previous = awake.until
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertEqual(awake.lidFailure, .busy)
        XCTAssertFalse(awake.lidApplied)
        XCTAssertEqual(awake.until, previous)
        fail = false
        awake.setLidEnabled(true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertNil(awake.lidFailure)
        XCTAssertTrue(awake.lidApplied)
    }

    func testLateFailureCannotReplaceTheResultOfNewerOffIntent() async {
        let wasSnapshot = Snapshot.active
        Snapshot.active = true
        defer { Snapshot.active = wasSnapshot }
        var reply: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { on, _ in
            if on { return try await withCheckedThrowingContinuation { reply = $0 } }
            return false
        })
        defer { awake.deactivate(silent: true) }
        awake.setLidEnabled(true)
        for _ in 0..<100 where reply == nil { await Task.yield() }
        awake.setLidEnabled(false)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        reply?.resume(throwing: HardwareReason.busy)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(awake.lidFailure)
        XCTAssertFalse(awake.lidApplied)
    }

    func testIndicatorFollowsTheClickBeforeTheServiceReplies() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        var reply: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { _, _ in
            try await withCheckedThrowingContinuation { reply = $0 }
        })
        awake.deactivate(silent: true)
        awake.toggleLid()
        XCTAssertTrue(awake.lidShown)
        XCTAssertFalse(awake.lidApplied)
        for _ in 0..<100 where reply == nil { await Task.yield() }
        XCTAssertTrue(awake.lidShown)
        reply?.resume(returning: true)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertTrue(awake.lidShown)
        XCTAssertTrue(awake.lidApplied)
        reply = nil
        awake.toggleLid()
        XCTAssertFalse(awake.lidShown)
        for _ in 0..<100 where reply == nil { await Task.yield() }
        reply?.resume(returning: false)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertFalse(awake.lidApplied)
    }

    func testRefusedEnableTurnsTheIndicatorBackOffWithItsReason() async {
        let saved = Snapshot.active; Snapshot.active = true
        defer { Snapshot.active = saved }
        var reply: CheckedContinuation<Bool, Error>?
        let awake = KeepAwakeController(demo: true, protectedLid: { _, _ in
            try await withCheckedThrowingContinuation { reply = $0 }
        })
        awake.deactivate(silent: true)
        awake.toggleLid()
        XCTAssertTrue(awake.lidShown)
        for _ in 0..<100 where reply == nil { await Task.yield() }
        reply?.resume(throwing: HardwareReason.thermal)
        for _ in 0..<100 where awake.lidChanging { await Task.yield() }
        XCTAssertFalse(awake.lidShown)
        XCTAssertEqual(awake.lidFailure, .thermal)
    }
}
