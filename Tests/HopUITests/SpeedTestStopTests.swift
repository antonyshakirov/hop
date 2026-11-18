import XCTest
@testable import Hop

@MainActor
final class SpeedTestStopTests: XCTestCase {
    func testStopEndsTheRunAtOnceAndKeepsTheNumbersSeenSoFar() async {
        let defaults = UserDefaults.standard
        let keys = ["speedLastDown", "speedLastUp", "speedLastRpm", "speedLastAt", "speedLastNet"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        let controller = SpeedTestController(measure: { _, stop in
            stop.seen(down: 480)
            while !stop.raised { usleep(10_000) }
            usleep(300_000)
            return .stopped(down: stop.down, up: stop.up)
        })
        controller.run()
        XCTAssertTrue(controller.isRunning)
        try? await Task.sleep(nanoseconds: 100_000_000)
        controller.stop()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.last?.down, 480)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.failed)
    }

    func testALateReplyFromAStoppedRunCannotEndTheNextRun() async {
        let controller = SpeedTestController(measure: { _, stop in
            while !stop.raised { usleep(10_000) }
            usleep(300_000)
            return .failed
        })
        controller.run()
        controller.stop()
        controller.run()
        XCTAssertTrue(controller.isRunning)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(controller.isRunning)
        XCTAssertFalse(controller.failed)
        controller.stop()
    }
}
