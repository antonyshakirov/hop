import XCTest
@testable import HopCore

/// The panel is one view: a change that reaches it rebuilds every module in it.
/// The signature is what says a change is worth that, and a passing second is not.
final class ClockSignatureTests: XCTestCase {
    private var clock = Date(timeIntervalSinceReferenceDate: 1_000)

    private func engine() -> TimerEngine {
        TimerEngine(duration: 600, now: { self.clock })
    }

    func testASecondPassingChangesNothing() {
        let engine = engine()
        engine.start()
        let before = engine.signature
        for _ in 0..<12 {
            clock += 0.25
            engine.tick()
        }
        XCTAssertNotEqual(engine.heartbeat, before.deadline, "the clock did run")
        XCTAssertEqual(engine.signature, before)
    }

    func testStartingChangesIt() {
        let engine = engine()
        let before = engine.signature
        engine.start()
        XCTAssertNotEqual(engine.signature, before)
    }

    func testPausingAndResumingChangeIt() {
        let engine = engine()
        engine.start()
        let running = engine.signature
        engine.pause()
        let paused = engine.signature
        XCTAssertNotEqual(paused, running)
        engine.resume()
        XCTAssertNotEqual(engine.signature, paused)
    }

    func testResettingChangesIt() {
        let engine = engine()
        engine.start()
        let running = engine.signature
        engine.reset()
        XCTAssertNotEqual(engine.signature, running)
    }

    func testSettingTheDurationChangesIt() {
        let engine = engine()
        let before = engine.signature
        engine.setDuration(900)
        XCTAssertNotEqual(engine.signature, before)
    }

    func testAdjustingAStandingClockChangesIt() {
        let engine = engine()
        let before = engine.signature
        engine.adjust(by: 60)
        XCTAssertNotEqual(engine.signature, before)
    }

    func testAdjustingARunningClockChangesIt() {
        let engine = engine()
        engine.start()
        let running = engine.signature
        engine.adjust(by: 60)
        XCTAssertNotEqual(engine.signature, running, "the deadline moved")
    }

    func testSwitchingToTheStopwatchChangesIt() {
        let engine = engine()
        let before = engine.signature
        engine.setStopwatch(true)
        XCTAssertNotEqual(engine.signature, before)
    }

    func testFinishingChangesIt() {
        let engine = engine()
        engine.setDuration(1)
        engine.start()
        let running = engine.signature
        clock += 2
        engine.tick()
        XCTAssertEqual(engine.state, .finished)
        XCTAssertNotEqual(engine.signature, running)
    }

    func testAcknowledgingAFinishChangesIt() {
        let engine = engine()
        engine.setDuration(1)
        engine.start()
        clock += 2
        engine.tick()
        let blinking = engine.signature
        engine.acknowledgeFinish()
        XCTAssertNotEqual(engine.signature, blinking)
    }

    func testAFinishedClockGoesOnPulsingWithoutChangingIt() {
        let engine = engine()
        engine.setDuration(1)
        engine.start()
        clock += 2
        engine.tick()
        engine.acknowledgeFinish()
        let settled = engine.signature
        for _ in 0..<12 {
            clock += 0.25
            engine.tick()
        }
        XCTAssertEqual(engine.signature, settled)
    }
}
