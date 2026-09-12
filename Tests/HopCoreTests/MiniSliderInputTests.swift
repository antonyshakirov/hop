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

    // MARK: - filterDigits (what the field accepts while someone is typing)

    func testLettersAreStrippedAsTheyreTyped() {
        XCTAssertEqual(MiniSliderInput.filterDigits("1sdcv", range: 1...100), "1")
        XCTAssertEqual(MiniSliderInput.filterDigits("sdcv", range: 1...100), "")
    }

    func testDigitsAlonePassThroughUnchanged() {
        XCTAssertEqual(MiniSliderInput.filterDigits("60", range: 1...100), "60")
    }

    // 1...100's widest number ("100") is 3 digits — a fourth is dropped
    // rather than growing the field without limit.
    func testMoreDigitsThanTheRangeNeedsAreTruncated() {
        XCTAssertEqual(MiniSliderInput.filterDigits("12345", range: 1...100), "123")
        XCTAssertEqual(MiniSliderInput.filterDigits("1000", range: 1...100), "100")
    }

    func testTheDigitCapFollowsTheRangesOwnWidth() {
        XCTAssertEqual(MiniSliderInput.filterDigits("12345", range: 1...9), "1")
    }

    func testAMinusSignIsNotADigit() {
        XCTAssertEqual(MiniSliderInput.filterDigits("-20", range: 1...100), "20")
    }
}
