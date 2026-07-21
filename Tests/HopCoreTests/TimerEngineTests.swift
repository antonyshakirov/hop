import XCTest
@testable import HopCore

final class TimerEngineTests: XCTestCase {
    private var clock: Date!
    private var engine: TimerEngine!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSinceReferenceDate: 1_000_000)
        engine = TimerEngine(duration: 10 * 60, now: { self.clock })
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    func testInitialStateIsIdleWithFullRemaining() {
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.remaining, 600)
    }

    func testPresetSetsDurationAndResets() {
        engine.setPreset(minutes: 30)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.remaining, 1800)
    }

    func testPresetWhileRunningPausesIntoStash() {
        engine.start()
        advance(60)
        engine.setPreset(minutes: 5)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.remaining, 300)
        XCTAssertEqual(engine.stash?.remaining ?? -1, 540, accuracy: 0.001)
        XCTAssertEqual(engine.stash?.duration, 600)
    }

    func testSetDurationInIdle() {
        engine.setDuration(17 * 60)
        XCTAssertEqual(engine.remaining, 1020)
        // sub-minute seconds are valid: digits are set directly
        engine.setDuration(10)
        XCTAssertEqual(engine.remaining, 10)
        engine.setDuration(-5)
        XCTAssertEqual(engine.remaining, 0)
    }

    func testSetStopwatchAllowedFromPause() {
        engine.start()
        advance(60)
        engine.pause()
        engine.setStopwatch(true)
        XCTAssertTrue(engine.isStopwatch)
        XCTAssertEqual(engine.state, .idle)
    }

    func testSetStopwatchIgnoredWhileRunning() {
        engine.start()
        advance(10)
        engine.setStopwatch(true)
        XCTAssertFalse(engine.isStopwatch)
        XCTAssertEqual(engine.state, .running)
    }

    func testStartWithZeroDurationFinishesImmediately() {
        engine.setDuration(0)
        engine.start()
        XCTAssertEqual(engine.state, .finished)
        XCTAssertEqual(engine.remaining, 0)
    }

    func testSetDurationIgnoredWhileRunning() {
        engine.start()
        advance(60)
        engine.setDuration(30 * 60)
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.remaining, 540, accuracy: 0.001)
    }

    func testSetDurationFromFinishedGoesIdle() {
        engine.start()
        advance(700)
        engine.tick()
        engine.setDuration(15 * 60)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.remaining, 900)
    }

    func testStartingNewTimerDropsStash() {
        engine.start()
        advance(60)
        engine.setPreset(minutes: 5)
        XCTAssertNotNil(engine.stash)
        engine.start() // deliberately starting a new one — the pocket is cleared
        XCTAssertNil(engine.stash)
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.remaining, 300, accuracy: 0.001)
    }

    func testPresetWhileIdleDoesNotStash() {
        engine.setPreset(minutes: 5)
        XCTAssertNil(engine.stash)
    }

    func testRestoreStashResumesCountdown() {
        engine.start()
        advance(60)
        engine.setPreset(minutes: 5)
        engine.adjust(by: 300) // spinning the draft — the stash is untouched
        XCTAssertEqual(engine.stash?.remaining ?? -1, 540, accuracy: 0.001)

        engine.restoreStash()
        XCTAssertEqual(engine.state, .running)
        XCTAssertNil(engine.stash)
        XCTAssertEqual(engine.duration, 600)
        advance(40)
        XCTAssertEqual(engine.remaining, 500, accuracy: 0.001)
    }

    func testRestoreStashWithoutStashIsNoop() {
        engine.restoreStash()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.remaining, 600)
    }

    func testPresetWhilePausedStashesPausedRemaining() {
        engine.start()
        advance(100)
        engine.pause()
        engine.setPreset(minutes: 30)
        XCTAssertEqual(engine.stash?.remaining ?? -1, 500, accuracy: 0.001)
        engine.restoreStash()
        XCTAssertEqual(engine.state, .running)
        advance(100)
        XCTAssertEqual(engine.remaining, 400, accuracy: 0.001)
    }

    func testStartCountsDown() {
        engine.start()
        XCTAssertEqual(engine.state, .running)
        advance(90)
        XCTAssertEqual(engine.remaining, 510, accuracy: 0.001)
    }

    func testPauseFreezesRemaining() {
        engine.start()
        advance(100)
        engine.pause()
        XCTAssertEqual(engine.state, .paused)
        advance(500)
        XCTAssertEqual(engine.remaining, 500, accuracy: 0.001)
    }

    func testResumeContinuesFromPausedRemaining() {
        engine.start()
        advance(100)
        engine.pause()
        advance(999)
        engine.resume()
        XCTAssertEqual(engine.state, .running)
        advance(50)
        XCTAssertEqual(engine.remaining, 450, accuracy: 0.001)
    }

    func testAdjustIdleAddsAndClampsToZero() {
        engine.adjust(by: 300)
        XCTAssertEqual(engine.remaining, 900)
        engine.adjust(by: -300)
        engine.adjust(by: -300)
        engine.adjust(by: -300)
        XCTAssertEqual(engine.remaining, 0)
    }

    func testAdjustWhileRunningExtendsTarget() {
        engine.start()
        advance(60)
        engine.adjust(by: 300)
        XCTAssertEqual(engine.remaining, 840, accuracy: 0.001)
    }

    func testAdjustBelowZeroWhileRunningFinishes() {
        var finished = false
        engine.onFinish = { finished = true }
        engine.start()
        advance(60)
        engine.adjust(by: -600)
        XCTAssertEqual(engine.state, .finished)
        XCTAssertEqual(engine.remaining, 0)
        XCTAssertTrue(finished)
    }

    func testTickFiresFinishWhenTimeIsUp() {
        var finished = false
        engine.onFinish = { finished = true }
        engine.start()
        advance(600.5)
        engine.tick()
        XCTAssertEqual(engine.state, .finished)
        XCTAssertTrue(finished)
    }

    func testTickBeforeDeadlineDoesNotFinish() {
        engine.start()
        advance(599)
        engine.tick()
        XCTAssertEqual(engine.state, .running)
    }

    func testResetReturnsToIdleWithOriginalDuration() {
        engine.start()
        advance(120)
        engine.reset()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.remaining, 600)
    }

    func testToggleFromFinishedRestarts() {
        engine.start()
        advance(700)
        engine.tick()
        XCTAssertEqual(engine.state, .finished)
        engine.toggle()
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.remaining, 600, accuracy: 0.001)
    }

    func testAdjustFromFinishedGoesIdle() {
        engine.start()
        advance(700)
        engine.tick()
        engine.adjust(by: 300)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.remaining, 900)
    }

    // MARK: - Finish acknowledgment (blink calm-down on panel open)

    func testFreshFinishIsBlinkingUnacknowledged() {
        engine.setDuration(0)
        engine.start() // all-zero → instant finish
        XCTAssertEqual(engine.state, .finished)
        XCTAssertFalse(engine.finishAcknowledged)
        XCTAssertTrue(engine.isFinishBlinking)
    }

    func testAcknowledgeStopsBlinkButStaysFinished() {
        engine.setDuration(0)
        engine.start()
        engine.acknowledgeFinish()
        XCTAssertTrue(engine.finishAcknowledged)
        XCTAssertFalse(engine.isFinishBlinking)
        XCTAssertEqual(engine.state, .finished) // still finished, just calm
        XCTAssertEqual(engine.remaining, 0)
    }

    func testAcknowledgeIgnoredWhenNotFinished() {
        engine.acknowledgeFinish() // idle
        XCTAssertFalse(engine.finishAcknowledged)
        engine.start() // running
        engine.acknowledgeFinish()
        XCTAssertFalse(engine.finishAcknowledged)
        XCTAssertEqual(engine.state, .running)
    }

    func testAcknowledgeIsIdempotent() {
        engine.setDuration(0)
        engine.start()
        engine.acknowledgeFinish()
        engine.acknowledgeFinish()
        XCTAssertTrue(engine.finishAcknowledged)
        XCTAssertFalse(engine.isFinishBlinking)
    }

    func testNewFinishReblinksAfterAcknowledge() {
        engine.setDuration(0)
        engine.start()            // finished
        engine.acknowledgeFinish()
        XCTAssertFalse(engine.isFinishBlinking)
        engine.toggle()           // restart the same (zero) duration → finishes again
        XCTAssertEqual(engine.state, .finished)
        XCTAssertFalse(engine.finishAcknowledged) // fresh finish clears the flag
        XCTAssertTrue(engine.isFinishBlinking)
    }

    func testResetAfterAcknowledgeLeavesFinished() {
        engine.setDuration(0)
        engine.start()
        engine.acknowledgeFinish()
        engine.reset()
        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.isFinishBlinking) // idle never blinks
    }

    // MARK: - Finish-settled pulse (digits keep pulsing after acknowledge)

    func testAcknowledgeEntersFinishSettledAndPersists() {
        engine.setDuration(0)
        engine.start()
        XCTAssertFalse(engine.isFinishSettled) // fresh finish is blinking, not settled
        engine.acknowledgeFinish()
        XCTAssertTrue(engine.isFinishSettled)  // finished AND acknowledged
        XCTAssertFalse(engine.isFinishBlinking) // the two never overlap
        XCTAssertEqual(engine.state, .finished)
        // it does not clear on its own: the digits keep pulsing across ticks
        advance(5)
        engine.tick()
        advance(5)
        engine.tick()
        XCTAssertTrue(engine.isFinishSettled)
        XCTAssertEqual(engine.state, .finished)
    }

    func testResetClearsFinishSettled() {
        engine.setDuration(0)
        engine.start()
        engine.acknowledgeFinish()
        XCTAssertTrue(engine.isFinishSettled)
        engine.reset()
        XCTAssertFalse(engine.isFinishSettled)
    }

    func testNewCountdownClearsFinishSettled() {
        engine.setDuration(0)
        engine.start()
        engine.acknowledgeFinish()
        XCTAssertTrue(engine.isFinishSettled)
        engine.setDuration(60) // a real duration
        engine.start()         // start a new countdown
        XCTAssertEqual(engine.state, .running)
        XCTAssertFalse(engine.isFinishSettled)
    }

    func testDigitEntryClearsFinishSettled() {
        engine.setDuration(0)
        engine.start()
        engine.acknowledgeFinish()
        XCTAssertTrue(engine.isFinishSettled)
        // typing a digit routes through setDuration, which leaves the finished state
        engine.setDuration(120)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertFalse(engine.isFinishSettled)
    }
}

final class TimeFormattingTests: XCTestCase {
    func testDisplayFormatsZero() {
        XCTAssertEqual(TimeFormatting.display(0), "00:00:00")
    }

    func testDisplayFormatsMinutes() {
        XCTAssertEqual(TimeFormatting.display(300), "00:05:00")
    }

    func testDisplayFormatsHours() {
        XCTAssertEqual(TimeFormatting.display(3661), "01:01:01")
    }

    func testDisplayRoundsUpPartialSeconds() {
        XCTAssertEqual(TimeFormatting.display(299.4), "00:05:00")
    }

    func testDimCountStopsAtFirstSignificantDigit() {
        XCTAssertEqual(TimeFormatting.dimCount(for: "00:41:11"), 3)
        XCTAssertEqual(TimeFormatting.dimCount(for: "00:05:00"), 4)
        XCTAssertEqual(TimeFormatting.dimCount(for: "01:01:01"), 1)
        XCTAssertEqual(TimeFormatting.dimCount(for: "00:00:00"), 8)
    }

    func testShortFormat() {
        XCTAssertEqual(TimeFormatting.short(300), "05:00")
        XCTAssertEqual(TimeFormatting.short(3661), "1:01:01")
    }
}

final class CycleTests: XCTestCase {
    private var clock: Date!
    private var engine: TimerEngine!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSinceReferenceDate: 2_000_000)
        engine = TimerEngine(duration: 600, now: { self.clock })
    }

    private func advance(_ s: TimeInterval) { clock = clock.addingTimeInterval(s) }

    func testCycleRunsWorkThenRest() {
        var phaseChanges: [Bool] = []
        engine.onPhaseChange = { phaseChanges.append($0) }
        engine.startCycle(work: 1500, rest: 300, rounds: 2)

        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.cycle, .init(isWork: true, round: 1, rounds: 2))
        XCTAssertEqual(engine.remaining, 1500, accuracy: 0.001)

        advance(1501); engine.tick() // work ends → rest
        XCTAssertEqual(engine.state, .running)
        XCTAssertEqual(engine.cycle, .init(isWork: false, round: 1, rounds: 2))
        XCTAssertEqual(phaseChanges, [false])

        advance(301); engine.tick() // rest ends → work 2
        XCTAssertEqual(engine.cycle, .init(isWork: true, round: 2, rounds: 2))
        XCTAssertEqual(phaseChanges, [false, true])

        advance(1501); engine.tick() // last work ends → finish
        XCTAssertEqual(engine.state, .finished)
        XCTAssertNil(engine.cycle)
    }

    func testCycleSkipsLastRest() {
        engine.startCycle(work: 60, rest: 30, rounds: 1)
        advance(61); engine.tick()
        XCTAssertEqual(engine.state, .finished)
        XCTAssertNil(engine.cycle)
    }

    func testResetClearsCycle() {
        engine.startCycle(work: 60, rest: 30, rounds: 3)
        engine.reset()
        XCTAssertNil(engine.cycle)
        XCTAssertEqual(engine.state, .idle)
        advance(61); engine.tick()
        XCTAssertEqual(engine.state, .idle) // the queue is empty, nothing starts
    }

    func testManualStartDropsCycle() {
        engine.startCycle(work: 60, rest: 30, rounds: 3)
        engine.setPreset(minutes: 10)
        XCTAssertNil(engine.cycle)
    }
}

final class StopwatchTests: XCTestCase {
    private var clock: Date!
    private var engine: TimerEngine!

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSinceReferenceDate: 3_000_000)
        engine = TimerEngine(duration: 600, now: { self.clock })
    }

    private func advance(_ s: TimeInterval) { clock = clock.addingTimeInterval(s) }

    func testStopwatchCountsUp() {
        engine.setStopwatch(true)
        XCTAssertEqual(engine.elapsed, 0)
        engine.start()
        advance(65)
        XCTAssertEqual(engine.elapsed, 65, accuracy: 0.001)
        engine.tick()
        XCTAssertEqual(engine.state, .running) // no finish
    }

    func testStopwatchPauseResume() {
        engine.setStopwatch(true)
        engine.start()
        advance(30)
        engine.pause()
        advance(100)
        XCTAssertEqual(engine.elapsed, 30, accuracy: 0.001)
        engine.resume()
        advance(10)
        XCTAssertEqual(engine.elapsed, 40, accuracy: 0.001)
    }

    func testStopwatchResetAndExit() {
        engine.setStopwatch(true)
        engine.start()
        advance(30)
        engine.reset()
        XCTAssertEqual(engine.elapsed, 0)
        XCTAssertTrue(engine.isStopwatch) // the mode stays
        engine.setPreset(minutes: 25) // a preset switches back to timer mode
        XCTAssertFalse(engine.isStopwatch)
        XCTAssertEqual(engine.remaining, 1500)
    }
}

final class PreparedCycleTests: XCTestCase {
    func testPreparedCycleWaitsForPlay() {
        var clock = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let engine = TimerEngine(duration: 600, now: { clock })
        engine.prepareCycle(work: 1500, rest: 300, rounds: 3)
        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(engine.cycle, .init(isWork: true, round: 1, rounds: 3))
        XCTAssertEqual(engine.remaining, 1500) // the display shows the work phase

        engine.toggle() // play
        XCTAssertEqual(engine.state, .running)
        clock = clock.addingTimeInterval(1501)
        engine.tick()
        XCTAssertEqual(engine.cycle, .init(isWork: false, round: 1, rounds: 3))
    }
}
