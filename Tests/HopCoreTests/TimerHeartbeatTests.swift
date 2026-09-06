import XCTest
@testable import HopCore

/// Publishing the heartbeat rebuilds every view that reads the model, so a tick
/// that changes nothing on screen must not publish.
final class TimerHeartbeatTests: XCTestCase {
    private var clock = Date(timeIntervalSinceReferenceDate: 1_000)

    private func engine() -> TimerEngine {
        TimerEngine(duration: 600, now: { self.clock })
    }

    func testARunningClockPublishesOncePerSecond() {
        let engine = engine()
        engine.start()
        var beats = 0
        var last = engine.heartbeat
        for _ in 0..<8 {
            clock += 0.25
            engine.tick()
            if engine.heartbeat != last { beats += 1; last = engine.heartbeat }
        }
        XCTAssertEqual(beats, 2, "two publishes over two seconds, not eight")
    }

    func testTheFinishedStatePublishesTwicePerSecond() {
        XCTAssertTrue(TimerEngine.publishes(
            at: Date(timeIntervalSinceReferenceDate: 10.6),
            since: Date(timeIntervalSinceReferenceDate: 10.1),
            fineGrained: true))
        XCTAssertFalse(TimerEngine.publishes(
            at: Date(timeIntervalSinceReferenceDate: 10.4),
            since: Date(timeIntervalSinceReferenceDate: 10.1),
            fineGrained: true))
    }

    func testQuarterSecondsWithinOneSecondDoNotPublish() {
        XCTAssertFalse(TimerEngine.publishes(
            at: Date(timeIntervalSinceReferenceDate: 10.75),
            since: Date(timeIntervalSinceReferenceDate: 10.0),
            fineGrained: false))
    }

    /// The countdown still ends on the tick that finds it over, whatever the
    /// publishing rule says: accuracy is the ticker's job, not the heartbeat's.
    func testTheTimerStillFinishesOnTime() {
        let engine = engine()
        engine.setDuration(1)
        engine.start()
        clock += 0.25
        engine.tick()
        XCTAssertEqual(engine.state, .running)
        clock += 0.8
        engine.tick()
        XCTAssertEqual(engine.state, .finished)
    }
}
