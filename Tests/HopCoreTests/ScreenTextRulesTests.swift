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

    // MARK: - the link in a reading

    func testQRPayloadThatIsALinkIsOffered() {
        XCTAssertEqual(ScreenTextRules.link(in: "https://pay.example.com/i/8f21"),
                       "https://pay.example.com/i/8f21")
    }

    func testLinkIsFoundInsideRecognizedText() {
        let text = "Invoice 42\nPay at https://pay.example.com/i/8f21 before Friday"
        XCTAssertEqual(ScreenTextRules.link(in: text), "https://pay.example.com/i/8f21")
    }

    func testTheFirstLinkWinsWhenThereAreSeveral() {
        let text = "https://first.example/a\nhttps://second.example/b"
        XCTAssertEqual(ScreenTextRules.link(in: text), "https://first.example/a")
        // and the order is by POSITION, not by scheme
        XCTAssertEqual(ScreenTextRules.link(in: "http://plain.example x https://secure.example"),
                       "http://plain.example")
    }

    func testSchemeMatchIsCaseInsensitiveButTheAddressIsKeptVerbatim() {
        XCTAssertEqual(ScreenTextRules.link(in: "HTTPS://Example.com/Path"),
                       "HTTPS://Example.com/Path")
    }

    func testSentencePunctuationIsNotPartOfTheAddress() {
        XCTAssertEqual(ScreenTextRules.link(in: "see https://example.com."), "https://example.com")
        XCTAssertEqual(ScreenTextRules.link(in: "(https://example.com)"), "https://example.com")
        XCTAssertEqual(ScreenTextRules.link(in: "«https://example.com»"), "https://example.com")
    }

    func testBalancedBracketsStayInsideTheAddress() {
        let wiki = "https://example.org/wiki/Hop_(tool)"
        XCTAssertEqual(ScreenTextRules.link(in: wiki), wiki)
    }

    func testABareHostPayloadBecomesHTTPS() {
        XCTAssertEqual(ScreenTextRules.link(in: "example.com"), "https://example.com")
        XCTAssertEqual(ScreenTextRules.link(in: " example.com/menu \n"), "https://example.com/menu")
    }

    func testABareHostIsOnlyPromotedWhenItIsTheWholeReading() {
        // a file name in a code screenshot must never turn into a link
        XCTAssertNil(ScreenTextRules.link(in: "open readme.md and api.js"))
        XCTAssertNil(ScreenTextRules.link(in: "let path = docs/readme.md"))
    }

    func testVersionsAndNumbersAreNotLinks() {
        XCTAssertNil(ScreenTextRules.link(in: "1.5.1"))
        XCTAssertNil(ScreenTextRules.link(in: "v2.0"))
        XCTAssertNil(ScreenTextRules.link(in: "12.5"))
    }

    func testNonWebPayloadsAreNotOffered() {
        XCTAssertNil(ScreenTextRules.link(in: "mailto:hi@example.com"))
        XCTAssertNil(ScreenTextRules.link(in: "tel:+15550100"))
        XCTAssertNil(ScreenTextRules.link(in: "WIFI:S:Cafe;T:WPA;P:secret;;"))
        XCTAssertNil(ScreenTextRules.link(in: "file:///etc/passwd"))
        XCTAssertNil(ScreenTextRules.link(in: "hop://open/settings"))
        XCTAssertNil(ScreenTextRules.link(in: "hi@example.com"))
    }

    func testATruncatedSchemeIsNotALink() {
        XCTAssertNil(ScreenTextRules.link(in: "https://"))
        XCTAssertNil(ScreenTextRules.link(in: "read https:// carefully"))
    }

    func testPlainTextHasNoLink() {
        XCTAssertNil(ScreenTextRules.link(in: ""))
        XCTAssertNil(ScreenTextRules.link(in: "just some recognized words"))
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
