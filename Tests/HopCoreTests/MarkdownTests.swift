import XCTest
@testable import HopCore

final class MarkdownParserTests: XCTestCase {
    func testHeadingsByLevel() {
        XCTAssertEqual(MarkdownParser.blocks("# Title"), [.heading(level: 1, text: "Title")])
        XCTAssertEqual(MarkdownParser.blocks("### Deeper"), [.heading(level: 3, text: "Deeper")])
        XCTAssertEqual(MarkdownParser.blocks("## Closed ##"), [.heading(level: 2, text: "Closed")])
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownParser.blocks("#hashtag"), [.paragraph("#hashtag")])
        // seven hashes is past the deepest level markdown has
        XCTAssertEqual(MarkdownParser.blocks("####### too deep"), [.paragraph("####### too deep")])
    }

    func testWrappedLinesBecomeOneParagraph() {
        let markdown = "first line\nsecond line\n\nnext paragraph"
        XCTAssertEqual(MarkdownParser.blocks(markdown), [
            .paragraph("first line second line"),
            .paragraph("next paragraph"),
        ])
    }

    func testBulletsAndNumbers() {
        let markdown = "- one\n* two\n+ three\n\n1. first\n2) second"
        XCTAssertEqual(MarkdownParser.blocks(markdown), [
            .bullet("one"), .bullet("two"), .bullet("three"),
            .numbered(1, "first"), .numbered(2, "second"),
        ])
    }

    func testFencedCodeKeepsItsLinesVerbatim() {
        let markdown = "```swift\nlet x = 1\n\n    indented\n```\nafter"
        XCTAssertEqual(MarkdownParser.blocks(markdown), [
            .code(lines: ["let x = 1", "", "    indented"], language: "swift"),
            .paragraph("after"),
        ])
    }

    func testUnterminatedFenceStillClosesAtTheEnd() {
        XCTAssertEqual(MarkdownParser.blocks("```\nlonely"),
                       [.code(lines: ["lonely"], language: nil)])
    }

    func testRulesAndQuotes() {
        XCTAssertEqual(MarkdownParser.blocks("---"), [.rule])
        XCTAssertEqual(MarkdownParser.blocks("* * *"), [.rule])
        XCTAssertEqual(MarkdownParser.blocks("> quoted"), [.quote("quoted")])
    }

    func testCarriageReturnsDoNotLeakIntoText() {
        XCTAssertEqual(MarkdownParser.blocks("# Title\r\n\r\nbody"),
                       [.heading(level: 1, text: "Title"), .paragraph("body")])
    }

    func testEmptyInput() {
        XCTAssertEqual(MarkdownParser.blocks(""), [])
        XCTAssertEqual(MarkdownParser.blocks("\n\n  \n"), [])
    }
}

final class MarkdownInlineTests: XCTestCase {
    func testPlainTextIsOneSpan() {
        XCTAssertEqual(MarkdownInline.spans("just text"), [InlineSpan(text: "just text")])
    }

    func testBoldItalicAndCode() {
        XCTAssertEqual(MarkdownInline.spans("**bold**"), [InlineSpan(text: "bold", bold: true)])
        XCTAssertEqual(MarkdownInline.spans("__bold__"), [InlineSpan(text: "bold", bold: true)])
        XCTAssertEqual(MarkdownInline.spans("*soft*"), [InlineSpan(text: "soft", italic: true)])
        XCTAssertEqual(MarkdownInline.spans("`code`"), [InlineSpan(text: "code", code: true)])
    }

    func testMixedRunsKeepTheirOrder() {
        XCTAssertEqual(MarkdownInline.spans("a **b** c"), [
            InlineSpan(text: "a "),
            InlineSpan(text: "b", bold: true),
            InlineSpan(text: " c"),
        ])
    }

    func testUnmatchedMarkerStaysLiteral() {
        XCTAssertEqual(MarkdownInline.spans("2 * 3 = 6"), [InlineSpan(text: "2 * 3 = 6")])
        XCTAssertEqual(MarkdownInline.spans("**unclosed"), [InlineSpan(text: "**unclosed")])
    }

    func testEmptyMarkersAreLiteral() {
        XCTAssertEqual(MarkdownInline.spans("****"), [InlineSpan(text: "****")])
    }

    func testLinks() {
        XCTAssertEqual(MarkdownInline.spans("[Hop](https://example.com)"),
                       [InlineSpan(text: "Hop", link: "https://example.com")])
        XCTAssertEqual(MarkdownInline.spans("see [Hop](https://example.com) now"), [
            InlineSpan(text: "see "),
            InlineSpan(text: "Hop", link: "https://example.com"),
            InlineSpan(text: " now"),
        ])
    }

    func testBracketsWithoutAUrlAreLiteral() {
        XCTAssertEqual(MarkdownInline.spans("[not a link]"), [InlineSpan(text: "[not a link]")])
    }

    func testBackslashEscapesAMarker() {
        XCTAssertEqual(MarkdownInline.spans("\\*not italic\\*"), [InlineSpan(text: "*not italic*")])
    }

    func testEmptyStringHasNoSpans() {
        XCTAssertEqual(MarkdownInline.spans(""), [])
    }
}

final class MarkdownWriterTests: XCTestCase {
    func testBlocksRoundTripThroughTheWriter() {
        let blocks: [MarkdownBlock] = [
            .heading(level: 1, text: "Title"),
            .paragraph("Body text."),
            .bullet("one"),
            .numbered(2, "two"),
            .quote("quoted"),
            .code(lines: ["let x = 1"], language: "swift"),
            .rule,
        ]
        let text = MarkdownWriter.text(from: blocks)
        XCTAssertEqual(MarkdownParser.blocks(text), blocks)
    }

    func testFileEndsWithExactlyOneNewline() {
        let text = MarkdownWriter.text(from: [.paragraph("one")])
        XCTAssertEqual(text, "one\n")
    }

    func testParagraphStartingWithAMarkerIsEscaped() {
        // otherwise reopening the file would read it as a list or a heading
        let text = MarkdownWriter.text(from: [.paragraph("- not a list")])
        XCTAssertEqual(text, "\\- not a list\n")
        XCTAssertEqual(MarkdownParser.blocks(text), [.paragraph("\\- not a list")])
    }

    func testHeadingLevelIsClamped() {
        XCTAssertEqual(MarkdownWriter.text(from: [.heading(level: 9, text: "x")]), "###### x\n")
        XCTAssertEqual(MarkdownWriter.text(from: [.heading(level: 0, text: "x")]), "# x\n")
    }
}

final class DocumentHeuristicsTests: XCTestCase {
    func testBodySizeIsTheMostCommonSize() {
        XCTAssertEqual(DocumentHeuristics.bodySize([12, 12, 12, 24, 18]), 12)
    }

    func testBodySizeTieGoesToTheSmaller() {
        XCTAssertEqual(DocumentHeuristics.bodySize([12, 12, 18, 18]), 12)
    }

    func testBodySizeOfNothing() {
        XCTAssertNil(DocumentHeuristics.bodySize([]))
    }

    func testHeadingLevelsFollowRatios() {
        XCTAssertEqual(DocumentHeuristics.headingLevel(size: 24, body: 12), 1)
        XCTAssertEqual(DocumentHeuristics.headingLevel(size: 17, body: 12), 2)
        XCTAssertEqual(DocumentHeuristics.headingLevel(size: 14, body: 12), 3)
        XCTAssertNil(DocumentHeuristics.headingLevel(size: 12, body: 12))
        XCTAssertNil(DocumentHeuristics.headingLevel(size: 10, body: 12))
    }

    func testRatiosWorkAtAnyBodySize() {
        // a 10pt document and a 14pt one must classify the same way
        XCTAssertEqual(DocumentHeuristics.headingLevel(size: 20, body: 10),
                       DocumentHeuristics.headingLevel(size: 28, body: 14))
    }

    func testBoldAtBodySizeIsTheDeepestHeading() {
        XCTAssertEqual(DocumentHeuristics.headingLevel(size: 12, body: 12, bold: true), 3)
        XCTAssertNil(DocumentHeuristics.headingLevel(size: 9, body: 12, bold: true))
    }

    func testListItems() {
        XCTAssertEqual(DocumentHeuristics.listItem("• bullet"),
                       .init(ordered: false, number: nil, text: "bullet"))
        XCTAssertEqual(DocumentHeuristics.listItem("  - dash"),
                       .init(ordered: false, number: nil, text: "dash"))
        XCTAssertEqual(DocumentHeuristics.listItem("3) third"),
                       .init(ordered: true, number: 3, text: "third"))
        XCTAssertNil(DocumentHeuristics.listItem("plain line"))
        XCTAssertNil(DocumentHeuristics.listItem("- "))       // a marker alone is not an item
        XCTAssertNil(DocumentHeuristics.listItem("2026. was a year"))  // no marker space rule met
    }

    func testWrappedLineContinuesTheParagraph() {
        XCTAssertTrue(DocumentHeuristics.continuesParagraph(
            previous: "this sentence is long enough to", next: "wrap onto the next line"))
    }

    func testSentenceEndStartsANewParagraph() {
        XCTAssertFalse(DocumentHeuristics.continuesParagraph(
            previous: "the sentence ends here.", next: "and this is the next one"))
        XCTAssertFalse(DocumentHeuristics.continuesParagraph(
            previous: "a question?", next: "an answer"))
    }

    func testACapitalOrAListMarkerStartsANewParagraph() {
        XCTAssertFalse(DocumentHeuristics.continuesParagraph(
            previous: "a line without punctuation", next: "New paragraph"))
        XCTAssertFalse(DocumentHeuristics.continuesParagraph(
            previous: "a line without punctuation", next: "- a list item"))
        XCTAssertFalse(DocumentHeuristics.continuesParagraph(
            previous: "a line without punctuation", next: "2. second"))
    }

    func testEmptyLinesNeverContinue() {
        XCTAssertFalse(DocumentHeuristics.continuesParagraph(previous: "", next: "text"))
        XCTAssertFalse(DocumentHeuristics.continuesParagraph(previous: "text", next: "  "))
    }

    func testRuleLines() {
        XCTAssertTrue(DocumentHeuristics.isRuleLine("———"))
        XCTAssertTrue(DocumentHeuristics.isRuleLine("-----"))
        XCTAssertTrue(DocumentHeuristics.isRuleLine("___"))
        XCTAssertFalse(DocumentHeuristics.isRuleLine("--"))          // too short
        XCTAssertFalse(DocumentHeuristics.isRuleLine("— dash lead")) // real text
        XCTAssertFalse(DocumentHeuristics.isRuleLine(""))
    }

    func testLooksLikeHeadingIsConservative() {
        XCTAssertTrue(DocumentHeuristics.looksLikeHeading("Project overview"))
        XCTAssertFalse(DocumentHeuristics.looksLikeHeading("This is a full sentence that ends."))
        XCTAssertFalse(DocumentHeuristics.looksLikeHeading(""))
    }
}
