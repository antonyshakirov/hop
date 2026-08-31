import XCTest
@testable import HopCore

/// The zones a pointer lands in, and the characters each group lights up.
final class TimerDigitsTests: XCTestCase {

    private func unit(_ fraction: Double, hoursHidden: Bool = false) -> TimeInterval {
        TimerDigits.unit(atFraction: fraction, hoursHidden: hoursHidden)
    }

    func testTheDisplaySplitsIntoHoursMinutesAndSeconds() {
        XCTAssertEqual(unit(0), TimerDigits.hours)
        XCTAssertEqual(unit(0.5), TimerDigits.minutes)
        XCTAssertEqual(unit(1), TimerDigits.seconds)
    }

    func testTheZoneBordersHold() {
        XCTAssertEqual(unit(0.309), TimerDigits.hours)
        XCTAssertEqual(unit(0.31), TimerDigits.minutes)
        XCTAssertEqual(unit(0.649), TimerDigits.minutes)
        XCTAssertEqual(unit(0.65), TimerDigits.seconds)
    }

    /// The "units" style drops the hours under an hour, so the display carries
    /// two groups and the pointer must not land on a group that is not drawn.
    func testWithoutHoursTheDisplaySplitsInHalf() {
        XCTAssertEqual(unit(0.1, hoursHidden: true), TimerDigits.minutes)
        XCTAssertEqual(unit(0.49, hoursHidden: true), TimerDigits.minutes)
        XCTAssertEqual(unit(0.5, hoursHidden: true), TimerDigits.seconds)
    }

    /// A drag can travel past either edge of the display.
    func testAPointOutsideTheDisplayStillPicksTheNearestGroup() {
        XCTAssertEqual(unit(-0.4), TimerDigits.hours)
        XCTAssertEqual(unit(1.8), TimerDigits.seconds)
    }

    func testAGroupLightsUpItsOwnTwoDigitsAndNoColon() {
        XCTAssertEqual(TimerDigits.range(for: TimerDigits.hours), 0..<2)
        XCTAssertEqual(TimerDigits.range(for: TimerDigits.minutes), 3..<5)
        XCTAssertEqual(TimerDigits.range(for: TimerDigits.seconds), 6..<8)
    }
}
