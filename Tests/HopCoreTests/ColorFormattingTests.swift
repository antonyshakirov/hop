import XCTest
@testable import HopCore

final class ColorFormattingTests: XCTestCase {
    // MARK: - hex

    func testHexIsUppercaseAndPadded() {
        XCTAssertEqual(ColorFormatting.hex(r: 0, g: 0, b: 0), "#000000")
        XCTAssertEqual(ColorFormatting.hex(r: 255, g: 255, b: 255), "#FFFFFF")
        XCTAssertEqual(ColorFormatting.hex(r: 51, g: 102, b: 153), "#336699")
        XCTAssertEqual(ColorFormatting.hex(r: 1, g: 2, b: 3), "#010203")
    }

    func testComponentsOutOfRangeAreClamped() {
        XCTAssertEqual(ColorFormatting.hex(r: -20, g: 300, b: 128), "#00FF80")
        XCTAssertEqual(ColorFormatting.rgb(r: -1, g: 256, b: 10), "rgb(0, 255, 10)")
    }

    // MARK: - rgb

    func testRgbNotation() {
        XCTAssertEqual(ColorFormatting.rgb(r: 51, g: 102, b: 153), "rgb(51, 102, 153)")
    }

    // MARK: - hsl

    func testHslOfPrimaryColors() {
        XCTAssertEqual(ColorFormatting.hsl(r: 255, g: 0, b: 0), "hsl(0, 100%, 50%)")
        XCTAssertEqual(ColorFormatting.hsl(r: 0, g: 255, b: 0), "hsl(120, 100%, 50%)")
        XCTAssertEqual(ColorFormatting.hsl(r: 0, g: 0, b: 255), "hsl(240, 100%, 50%)")
    }

    func testHslOfGraysHasNoHueOrSaturation() {
        XCTAssertEqual(ColorFormatting.hsl(r: 0, g: 0, b: 0), "hsl(0, 0%, 0%)")
        XCTAssertEqual(ColorFormatting.hsl(r: 128, g: 128, b: 128), "hsl(0, 0%, 50%)")
        XCTAssertEqual(ColorFormatting.hsl(r: 255, g: 255, b: 255), "hsl(0, 0%, 100%)")
    }

    func testHslOfAMixedColor() {
        // #336699 — the blue channel wins, so the hue comes off the third branch
        XCTAssertEqual(ColorFormatting.hsl(r: 51, g: 102, b: 153), "hsl(210, 50%, 40%)")
    }

    func testHueNeverRoundsToAFullTurn() {
        // a hue a hair under 360° must stay in 0..<360, not read as a second turn
        let string = ColorFormatting.hsl(r: 255, g: 0, b: 1)
        XCTAssertEqual(string, "hsl(0, 100%, 50%)")
    }

    // MARK: - format switch

    func testStringFollowsTheChosenFormat() {
        XCTAssertEqual(ColorFormatting.string(.hex, r: 51, g: 102, b: 153), "#336699")
        XCTAssertEqual(ColorFormatting.string(.rgb, r: 51, g: 102, b: 153), "rgb(51, 102, 153)")
        XCTAssertEqual(ColorFormatting.string(.hsl, r: 51, g: 102, b: 153), "hsl(210, 50%, 40%)")
    }

    // MARK: - canonical / components round trip

    func testCanonicalHasNoHash() {
        XCTAssertEqual(ColorFormatting.canonical(r: 51, g: 102, b: 153), "336699")
    }

    func testComponentsRoundTrip() {
        for (r, g, b) in [(0, 0, 0), (255, 255, 255), (51, 102, 153), (7, 128, 200)] {
            let parsed = ColorFormatting.components(ColorFormatting.canonical(r: r, g: g, b: b))
            XCTAssertEqual(parsed?.r, r)
            XCTAssertEqual(parsed?.g, g)
            XCTAssertEqual(parsed?.b, b)
        }
    }

    func testComponentsAcceptsHashAndShorthand() {
        XCTAssertEqual(ColorFormatting.components("#336699")?.r, 51)
        let short = ColorFormatting.components("#f80")
        XCTAssertEqual(short?.r, 255)
        XCTAssertEqual(short?.g, 136)
        XCTAssertEqual(short?.b, 0)
    }

    func testComponentsRejectsNonColors() {
        XCTAssertNil(ColorFormatting.components(""))
        XCTAssertNil(ColorFormatting.components("hello!"))
        XCTAssertNil(ColorFormatting.components("#12345"))
        XCTAssertNil(ColorFormatting.components("rgb(1, 2, 3)"))
    }
}
