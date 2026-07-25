import XCTest
@testable import HopCore

final class ScreenTextRulesTests: XCTestCase {
    func testNothingReadGivesNothing() {
        XCTAssertNil(ScreenTextRules.assemble(lines: [], barcodes: []))
        XCTAssertNil(ScreenTextRules.assemble(lines: ["  ", "\n"], barcodes: [" "]))
    }

    func testTextLinesKeepTheirOrderAndLineBreaks() {
        let out = ScreenTextRules.assemble(lines: ["first line", "second line"], barcodes: [])
        XCTAssertEqual(out, "first line\nsecond line")
    }

    func testEachLineIsTrimmedAndEmptyLinesDrop() {
        let out = ScreenTextRules.assemble(lines: ["  padded  ", "", "   ", "\ttabbed"], barcodes: [])
        XCTAssertEqual(out, "padded\ntabbed")
    }

    func testRepeatedTextLinesAreKept() {
        // a table column can genuinely hold the same value twice
        let out = ScreenTextRules.assemble(lines: ["12", "12", "13"], barcodes: [])
        XCTAssertEqual(out, "12\n12\n13")
    }

    func testBarcodeWinsOverText() {
        let out = ScreenTextRules.assemble(
            lines: ["scan me to open the menu"],
            barcodes: ["https://example.com/menu"])
        XCTAssertEqual(out, "https://example.com/menu")
    }

    func testSeveralBarcodesAreJoinedAndDeduplicated() {
        let out = ScreenTextRules.assemble(
            lines: [],
            barcodes: ["https://a.example", "https://b.example", "https://a.example"])
        XCTAssertEqual(out, "https://a.example\nhttps://b.example")
    }

    func testEmptyBarcodePayloadFallsBackToText() {
        // a detected code whose payload didn't decode must not swallow the text
        let out = ScreenTextRules.assemble(lines: ["readable text"], barcodes: ["", "   "])
        XCTAssertEqual(out, "readable text")
    }

    func testSingleLineHasNoTrailingBreak() {
        XCTAssertEqual(ScreenTextRules.assemble(lines: ["one"], barcodes: []), "one")
    }

    // MARK: - reading order

    /// Vision's origin is bottom-left, so a HIGHER y is higher on screen.
    private func box(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: 0.1, height: 0.02)
    }

    func testReadingOrderGoesTopToBottom() {
        let boxes = [box(x: 0.1, y: 0.2), box(x: 0.1, y: 0.8), box(x: 0.1, y: 0.5)]
        XCTAssertEqual(ScreenTextRules.readingOrder(boxes), [1, 2, 0])
    }

    func testWordsOnOneLineGoLeftToRight() {
        let boxes = [box(x: 0.6, y: 0.5), box(x: 0.1, y: 0.5), box(x: 0.35, y: 0.5)]
        XCTAssertEqual(ScreenTextRules.readingOrder(boxes), [1, 2, 0])
    }

    func testVerticalNoiseDoesNotSplitALine() {
        // the same visual line, off by a thousandth: order must stay left-to-right
        let boxes = [box(x: 0.6, y: 0.5005), box(x: 0.1, y: 0.4998)]
        XCTAssertEqual(ScreenTextRules.readingOrder(boxes), [1, 0])
    }

    func testTwoColumnsReadRowByRow() {
        let boxes = [
            box(x: 0.05, y: 0.9), box(x: 0.55, y: 0.9),   // top row: left, right
            box(x: 0.05, y: 0.4), box(x: 0.55, y: 0.4),   // bottom row
        ]
        XCTAssertEqual(ScreenTextRules.readingOrder(boxes), [0, 1, 2, 3])
    }

    func testIdenticalBoxesKeepAStableOrder() {
        let boxes = [box(x: 0.2, y: 0.5), box(x: 0.2, y: 0.5)]
        XCTAssertEqual(ScreenTextRules.readingOrder(boxes), [0, 1])
    }

    func testEmptyInputGivesEmptyOrder() {
        XCTAssertEqual(ScreenTextRules.readingOrder([]), [])
    }
}
