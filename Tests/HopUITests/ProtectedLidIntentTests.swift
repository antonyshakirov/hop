import HopHardwareKit
import XCTest
@testable import Hop

@MainActor
final class ProtectedLidIntentTests: XCTestCase {
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

    func testChangingDurationDuringPendingLidEnableUpdatesTheRootDeadline() async {
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
        let firstDeadline = awake.until
        awake.activate(.init(label: "2h", seconds: 7200))
        firstReply?.resume(returning: true)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(deadlines.count, 2)
        XCTAssertEqual(deadlines.first!, firstDeadline)
        XCTAssertEqual(deadlines.last!, awake.until)
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
        awake.activate(.init(label: "2h", seconds: 7200))
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(awake.lidApplied)
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
}
