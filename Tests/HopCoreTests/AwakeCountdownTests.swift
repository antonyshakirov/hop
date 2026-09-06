import XCTest
@testable import HopCore

final class AwakeCountdownTests: XCTestCase {
    func testTheRowShowsWholeMinutesRoundedUp() {
        XCTAssertEqual(AwakeCountdown.minutes(remaining: 61), 2)
        XCTAssertEqual(AwakeCountdown.minutes(remaining: 60), 1)
        XCTAssertEqual(AwakeCountdown.minutes(remaining: 1), 1)
        XCTAssertEqual(AwakeCountdown.minutes(remaining: 0), 1)
    }

    /// An endless session shows the same sign for hours; publishing a heartbeat
    /// for it redraws the panel and the menu bar for nothing.
    func testAnEndlessSessionNeverPublishes() {
        XCTAssertFalse(AwakeCountdown.publishes(remaining: nil, shown: nil))
        XCTAssertFalse(AwakeCountdown.publishes(remaining: nil, shown: 5))
    }

    func testSecondsInsideOneMinuteDoNotPublish() {
        XCTAssertFalse(AwakeCountdown.publishes(remaining: 610, shown: 11))
        XCTAssertFalse(AwakeCountdown.publishes(remaining: 601, shown: 11))
    }

    func testCrossingAMinutePublishesOnce() {
        XCTAssertTrue(AwakeCountdown.publishes(remaining: 599, shown: 11))
        XCTAssertFalse(AwakeCountdown.publishes(remaining: 599, shown: 10))
    }
}
