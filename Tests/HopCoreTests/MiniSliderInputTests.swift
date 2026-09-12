import XCTest
@testable import HopCore

final class MiniSliderInputTests: XCTestCase {
    func testAnOrdinaryValueInRangePassesThrough() {
        XCTAssertEqual(MiniSliderInput.commit("60", range: 1...100, fallback: 55), 60)
    }

    func testAboveTheUpperBoundClampsDown() {
        XCTAssertEqual(MiniSliderInput.commit("500", range: 1...100, fallback: 55), 100)
    }

    func testBelowTheLowerBoundClampsUp() {
        XCTAssertEqual(MiniSliderInput.commit("0", range: 1...100, fallback: 55), 1)
        XCTAssertEqual(MiniSliderInput.commit("-20", range: 1...100, fallback: 55), 1)
    }

    func testNonNumericTextFallsBackRatherThanZeroing() {
        XCTAssertEqual(MiniSliderInput.commit("abc", range: 1...100, fallback: 55), 55)
    }

    func testEmptyTextFallsBack() {
        XCTAssertEqual(MiniSliderInput.commit("", range: 1...100, fallback: 55), 55)
    }

    // Int("60.5") is nil — a decimal is treated as a typo in progress, not a
    // new value, exactly like an empty or non-numeric field.
    func testADecimalFallsBackRatherThanTruncating() {
        XCTAssertEqual(MiniSliderInput.commit("60.5", range: 1...100, fallback: 55), 55)
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(MiniSliderInput.commit("  60  ", range: 1...100, fallback: 55), 60)
    }

    func testExactlyOnEitherBoundIsAccepted() {
        XCTAssertEqual(MiniSliderInput.commit("1", range: 1...100, fallback: 55), 1)
        XCTAssertEqual(MiniSliderInput.commit("100", range: 1...100, fallback: 55), 100)
    }
}
