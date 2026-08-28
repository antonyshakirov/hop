import XCTest
@testable import HopCore

final class DurationFieldTests: XCTestCase {
    // MARK: - What the field shows

    func testItAlwaysSpellsOutAllThreeParts() {
        XCTAssertEqual(DurationField.text(for: 0), "0:00:00")
        XCTAssertEqual(DurationField.text(for: 45 * 60), "0:45:00")
        XCTAssertEqual(DurationField.text(for: 11 * 3600), "11:00:00")
        XCTAssertEqual(DurationField.text(for: 11 * 3600 + 2 * 60 + 2), "11:02:02")
    }

    func testHoursAreNotCapped() {
        // a long-lived task can hold hundreds of hours
        XCTAssertEqual(DurationField.text(for: 1234 * 3600 + 59 * 60 + 59), "1234:59:59")
    }

    // MARK: - What it reads back

    func testItReadsItsOwnOutput() {
        for seconds in [0, 59, 600, 3661, 11 * 3600 + 2 * 60 + 2, 1234 * 3600] {
            let text = DurationField.text(for: TimeInterval(seconds))
            XCTAssertEqual(DurationField.parse(text), TimeInterval(seconds), text)
        }
    }

    func testPartsAreCountedFromTheRight() {
        XCTAssertEqual(DurationField.parse("30"), 30)          // seconds
        XCTAssertEqual(DurationField.parse("2:30"), 150)       // minutes and seconds
        XCTAssertEqual(DurationField.parse("1:02:30"), 3750)   // hours as well
    }

    func testOverLargePartsAddUpInsteadOfBeingRefused() {
        XCTAssertEqual(DurationField.parse("90:00"), 5400)     // ninety minutes
        XCTAssertEqual(DurationField.parse("0:0:120"), 120)
    }

    func testAnEmptySlotReadsAsZero() {
        XCTAssertEqual(DurationField.parse("1::30"), 3630)
    }

    func testNonsenseIsRefused() {
        XCTAssertNil(DurationField.parse(""))
        XCTAssertNil(DurationField.parse("   "))
        XCTAssertNil(DurationField.parse("abc"))
        XCTAssertNil(DurationField.parse("1:2:3:4"))
        XCTAssertNil(DurationField.parse("-5"))
    }
}
