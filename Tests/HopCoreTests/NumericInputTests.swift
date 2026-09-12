import XCTest
@testable import HopCore

final class NumericInputTests: XCTestCase {
    func testAnOrdinaryValueInRangePassesThrough() {
        XCTAssertEqual(NumericInput.commit("60", range: 1...100, fallback: 55), 60)
    }

    func testAboveTheUpperBoundClampsDown() {
        XCTAssertEqual(NumericInput.commit("500", range: 1...100, fallback: 55), 100)
    }

    func testBelowTheLowerBoundClampsUp() {
        XCTAssertEqual(NumericInput.commit("0", range: 1...100, fallback: 55), 1)
        XCTAssertEqual(NumericInput.commit("-20", range: 1...100, fallback: 55), 1)
    }

    func testNonNumericTextFallsBackRatherThanZeroing() {
        XCTAssertEqual(NumericInput.commit("abc", range: 1...100, fallback: 55), 55)
    }

    func testEmptyTextFallsBack() {
        XCTAssertEqual(NumericInput.commit("", range: 1...100, fallback: 55), 55)
    }

    func testADecimalFallsBackRatherThanTruncating() {
        XCTAssertEqual(NumericInput.commit("60.5", range: 1...100, fallback: 55), 55)
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(NumericInput.commit("  60  ", range: 1...100, fallback: 55), 60)
    }

    func testExactlyOnEitherBoundIsAccepted() {
        XCTAssertEqual(NumericInput.commit("1", range: 1...100, fallback: 55), 1)
        XCTAssertEqual(NumericInput.commit("100", range: 1...100, fallback: 55), 100)
    }

    func testAnUnparseablyLongRunFallsBack() {
        XCTAssertEqual(NumericInput.commit(String(repeating: "9", count: 30),
                                           range: 1...100, fallback: 55), 55)
    }

    func testLettersAreStrippedAsTheyreTyped() {
        XCTAssertEqual(NumericInput.filterDigits("1sdcv", range: 1...100), "1")
        XCTAssertEqual(NumericInput.filterDigits("sdcv", range: 1...100), "")
    }

    func testDigitsAlonePassThroughUnchanged() {
        XCTAssertEqual(NumericInput.filterDigits("60", range: 1...100), "60")
    }

    func testMoreDigitsThanTheRangeNeedsAreTruncated() {
        XCTAssertEqual(NumericInput.filterDigits("12345", range: 1...100), "123")
        XCTAssertEqual(NumericInput.filterDigits("1000", range: 1...100), "100")
    }

    func testTheDigitCapFollowsTheRangesOwnWidth() {
        XCTAssertEqual(NumericInput.filterDigits("12345", range: 1...9), "1")
        XCTAssertEqual(NumericInput.filterDigits("12345", range: 1...9999), "1234")
    }

    func testAMinusSignIsNotADigit() {
        XCTAssertEqual(NumericInput.filterDigits("-20", range: 1...100), "20")
    }

    // Character.isNumber is true for ٠-٩; Int(_:) reads none of them.
    func testDigitsOfOtherScriptsAreDroppedRatherThanShown() {
        XCTAssertEqual(NumericInput.filterDigits("٦٠", range: 1...100), "")
        XCTAssertEqual(NumericInput.filterDigits("6٠0", range: 1...100), "60")
        XCTAssertEqual(NumericInput.filterDigits("½", range: 1...100), "")
        XCTAssertEqual(NumericInput.filterDigits("²", range: 1...100), "")
    }

    // "1" on its way to "15" in 10...20 must survive typing; commit clamps it.
    func testATooSmallDigitSurvivesTypingAndClampsOnCommit() {
        XCTAssertEqual(NumericInput.filterDigits("5", range: 10...20), "5")
        XCTAssertEqual(NumericInput.commit("5", range: 10...20, fallback: 15), 10)
    }

    func testTheDigitCapIsNeverZero() {
        XCTAssertEqual(NumericInput.filterDigits("7", maxDigits: 0), "7")
    }

    func testClampBringsAValueInsideTheRange() {
        XCTAssertEqual(NumericInput.clamp(120, into: 1...100), 100)
        XCTAssertEqual(NumericInput.clamp(-5, into: 1...100), 1)
        XCTAssertEqual(NumericInput.clamp(42, into: 1...100), 42)
    }
}
