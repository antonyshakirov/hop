import XCTest
@testable import HopCore

final class TimerPluginLifecycleTests: XCTestCase {
    func testPausedPluginBreakKeepsOriginAndManualNewTimerSupersedesRevision() {
        var moment = Date()
        let timer = TimerEngine(now: { moment })
        timer.startPluginTimer(seconds: 60, owner: "auto-break")
        let started = timer.controlRevision
        let session = timer.controlSession
        timer.pause()
        XCTAssertGreaterThan(timer.controlRevision, started)
        XCTAssertEqual(timer.startedByPlugin, "auto-break")
        timer.adjust(by: 5)
        XCTAssertEqual(timer.startedByPlugin, "auto-break")
        timer.resume()
        XCTAssertEqual(timer.controlSession, session)
        XCTAssertEqual(timer.startedByPlugin, "auto-break")
        moment.addTimeInterval(66)
        timer.tick()
        XCTAssertEqual(timer.state, .finished)
        XCTAssertEqual(timer.startedByPlugin, "auto-break")
        timer.reset()
        timer.setDuration(300)
        timer.start()
        XCTAssertNil(timer.startedByPlugin)
        XCTAssertNotEqual(timer.controlSession, session)
        XCTAssertGreaterThan(timer.controlRevision, started)
        timer.reset()
    }
}
