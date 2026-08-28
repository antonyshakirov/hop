import XCTest
@testable import HopCore

final class TrackerMomentTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    // MARK: - Field order follows the locale

    func testMostOfTheWorldReadsDayFirst() {
        XCTAssertEqual(TrackerMoment.order(template: "dd.MM.y"),
                       [.day, .month, .year])
    }

    func testTheUsReadsMonthFirst() {
        XCTAssertEqual(TrackerMoment.order(template: "M/d/yy"),
                       [.month, .day, .year])
    }

    func testEastAsiaReadsYearFirst() {
        XCTAssertEqual(TrackerMoment.order(template: "y/M/d"),
                       [.year, .month, .day])
    }

    func testAMissingPartIsStillOffered() {
        // a template without a year must not leave the row with two fields
        XCTAssertEqual(TrackerMoment.order(template: "d MMM"), [.day, .month, .year])
        XCTAssertEqual(TrackerMoment.order(template: ""), [.day, .month, .year])
    }

    // MARK: - A day that exists

    func testTheThirtyFirstOfAShortMonthBecomesItsLast() {
        XCTAssertEqual(TrackerMoment.clampedDay(31, month: 4, year: 2026, calendar: calendar), 30)
        XCTAssertEqual(TrackerMoment.clampedDay(31, month: 2, year: 2026, calendar: calendar), 28)
    }

    func testALeapYearKeepsItsTwentyNinth() {
        XCTAssertEqual(TrackerMoment.clampedDay(29, month: 2, year: 2028, calendar: calendar), 29)
        XCTAssertEqual(TrackerMoment.clampedDay(29, month: 2, year: 2026, calendar: calendar), 28)
    }

    func testNonsenseNumbersLandOnSomethingReal() {
        XCTAssertEqual(TrackerMoment.clampedDay(0, month: 5, year: 2026, calendar: calendar), 1)
        XCTAssertEqual(TrackerMoment.clampedDay(99, month: 5, year: 2026, calendar: calendar), 31)
        XCTAssertEqual(TrackerMoment.clampedDay(15, month: 13, year: 2026, calendar: calendar), 15)
    }

    // MARK: - Building the moment

    func testTheNumbersBecomeTheDateTheyDescribe() {
        let date = TrackerMoment.date(year: 2026, month: 3, day: 5, hour: 14, minute: 30,
                                      calendar: calendar)
        let parts = TrackerMoment.parts(of: date!, calendar: calendar)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 3)
        XCTAssertEqual(parts.day, 5)
        XCTAssertEqual(parts.hour, 14)
        XCTAssertEqual(parts.minute, 30)
    }

    func testAnImpossibleDayIsBuiltAsItsMonthsLast() {
        let date = TrackerMoment.date(year: 2026, month: 2, day: 31, hour: 9, minute: 0,
                                      calendar: calendar)
        XCTAssertEqual(TrackerMoment.parts(of: date!, calendar: calendar).day, 28)
    }

    func testOutOfRangeClockValuesAreBroughtBackIn() {
        let date = TrackerMoment.date(year: 2026, month: 6, day: 1, hour: 99, minute: -5,
                                      calendar: calendar)
        let parts = TrackerMoment.parts(of: date!, calendar: calendar)
        XCTAssertEqual(parts.hour, 23)
        XCTAssertEqual(parts.minute, 0)
    }

    func testSecondsAreAlwaysZeroed() {
        // a session logged by hand starts on the minute, not on whatever second
        // the editor happened to open
        let date = TrackerMoment.date(year: 2026, month: 6, day: 1, hour: 10, minute: 15,
                                      calendar: calendar)!
        XCTAssertEqual(calendar.component(.second, from: date), 0)
    }

    func testReadingAndRebuildingIsTheSameMoment() {
        let original = calendar.date(from: DateComponents(year: 2024, month: 12, day: 31,
                                                          hour: 23, minute: 59))!
        let parts = TrackerMoment.parts(of: original, calendar: calendar)
        let rebuilt = TrackerMoment.date(year: parts.year, month: parts.month, day: parts.day,
                                         hour: parts.hour, minute: parts.minute,
                                         calendar: calendar)
        XCTAssertEqual(rebuilt, original)
    }
}
