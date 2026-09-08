import XCTest
@testable import HopCore

final class MarkupBlurTests: XCTestCase {
    /// The lightest setting has to be light enough to read through, or the
    /// bottom half of the slider is wasted.
    func testTheLightestBlurIsBarelyThere() {
        XCTAssertLessThan(MarkupBlur.radius(forStrength: 1), 1)
        XCTAssertLessThan(MarkupBlur.radius(forStrength: 3), 2)
    }

    /// And the heaviest has to hide a line of text without going to soup.
    func testTheHeaviestBlurStaysWithinReason() {
        XCTAssertEqual(MarkupBlur.radius(forStrength: 10), 15, accuracy: 0.01)
    }

    /// Every step has to be a step: on a straight scale the top half looked
    /// the same all the way along.
    func testEveryStepIsHeavierThanTheOneBeforeIt() {
        for strength in 2...10 {
            XCTAssertGreaterThan(MarkupBlur.radius(forStrength: strength),
                                 MarkupBlur.radius(forStrength: strength - 1))
            XCTAssertGreaterThan(MarkupBlur.mosaic(forStrength: strength),
                                 MarkupBlur.mosaic(forStrength: strength - 1))
        }
    }

    /// The curve bends the other way from a straight line: the first half of
    /// the slider covers less than a quarter of the range.
    func testTheScaleIsGentleAtItsFootAndSteepAtItsHead() {
        let full = MarkupBlur.radius(forStrength: 10) - MarkupBlur.radius(forStrength: 1)
        let firstHalf = MarkupBlur.radius(forStrength: 5) - MarkupBlur.radius(forStrength: 1)
        XCTAssertLessThan(firstHalf / full, 0.3)
    }

    func testAnAbsurdStrengthIsBroughtBackIntoRange() {
        XCTAssertEqual(MarkupBlur.radius(forStrength: -4), MarkupBlur.radius(forStrength: 1))
        XCTAssertEqual(MarkupBlur.mosaic(forStrength: 99), MarkupBlur.mosaic(forStrength: 10))
    }
}
