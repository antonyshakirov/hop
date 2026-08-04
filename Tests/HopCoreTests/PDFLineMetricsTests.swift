import XCTest
@testable import HopCore

final class PDFLineMetricsTests: XCTestCase {
    private func segment(
        _ y: Double, _ size: Double, bold: Bool = false, glyphs: Int = 40
    ) -> PDFLineMetrics.Segment {
        PDFLineMetrics.Segment(y: y, size: size, bold: bold, glyphs: glyphs)
    }

    /// A line of `size` type sitting on `baseline`, boxed the way PDFKit boxes
    /// one: a little below the baseline for the descenders, the rest above.
    private func line(baseline: Double, size: Double) -> PDFLineMetrics.LineBox {
        PDFLineMetrics.LineBox(minY: baseline - size * 0.21, maxY: baseline + size * 0.79)
    }

    // MARK: - Matching a line to what painted it

    func testALineTakesTheSizeOfTheRunInsideIt() {
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 700, size: 20), line(baseline: 680, size: 11),
                    line(baseline: 660, size: 11)],
            segments: [segment(700, 20, bold: true), segment(680, 11), segment(660, 11)])
        XCTAssertEqual(metrics[0], PDFLineMetrics.Metric(size: 20, bold: true))
        XCTAssertEqual(metrics[1], PDFLineMetrics.Metric(size: 11, bold: false))
        XCTAssertEqual(metrics[2], PDFLineMetrics.Metric(size: 11, bold: false))
    }

    func testABaselineJustOutsideTheBoxStillBelongsToTheLine() {
        // the box and the baseline are measured by different machinery
        let metrics = PDFLineMetrics.match(
            lines: [PDFLineMetrics.LineBox(minY: 700, maxY: 709)], segments: [segment(699, 11)])
        XCTAssertEqual(metrics[0]?.size, 11)
    }

    func testALineFarFromEverySegmentFindsNothing() {
        let metrics = PDFLineMetrics.match(lines: [line(baseline: 400, size: 11)],
                                           segments: [segment(700, 11)])
        XCTAssertNil(metrics[0])
    }

    func testTheNeighbouringLineDoesNotLendItsSize() {
        // a body line under a heading must not be read as a heading: the
        // heading's baseline is outside this line's box
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 680, size: 11)],
            segments: [segment(700, 24, bold: true), segment(680, 11)])
        XCTAssertEqual(metrics[0], PDFLineMetrics.Metric(size: 11, bold: false))
    }

    func testTheRunCarryingMostOfTheTextDecidesTheLine() {
        // a heading with a footnote mark after it is still a heading
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 700, size: 24)],
            segments: [segment(700, 24, bold: true, glyphs: 30), segment(700, 8, glyphs: 1)])
        XCTAssertEqual(metrics[0], PDFLineMetrics.Metric(size: 24, bold: true))
    }

    func testALargeStrayCharacterDoesNotPromoteABodyLine() {
        // a drop cap or a page-edge stamp next to ordinary text: the text wins
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 500, size: 11)],
            segments: [segment(500, 11, glyphs: 70), segment(500, 20, glyphs: 2)])
        XCTAssertEqual(metrics[0], PDFLineMetrics.Metric(size: 11, bold: false))
    }

    func testAnEvenSplitGoesToTheLargerSize() {
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 300, size: 18)],
            segments: [segment(300, 18, glyphs: 10), segment(300, 11, glyphs: 10)])
        XCTAssertEqual(metrics[0]?.size, 18)
    }

    func testAPageWithNoSegmentsMatchesNothingAtAll() {
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 700, size: 11), line(baseline: 680, size: 11)], segments: [])
        XCTAssertEqual(metrics.count, 2)
        XCTAssertNil(metrics[0])
        XCTAssertNil(metrics[1])
    }

    func testEveryLineGetsAnAnswerSlotEvenWhenUnmatched() {
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 700, size: 11), line(baseline: 100, size: 11),
                    line(baseline: 680, size: 11)],
            segments: [segment(700, 11), segment(680, 11)])
        XCTAssertEqual(metrics.count, 3)
        XCTAssertNotNil(metrics[0])
        XCTAssertNil(metrics[1])
        XCTAssertNotNil(metrics[2])
    }

    func testASizeIsRoundedBeforeRunsAreCounted() {
        // 11.02 and 11.04 are the same type, and must not split the vote and
        // hand the line to a smaller run that happens to be whole
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 700, size: 11)],
            segments: [segment(700, 11.02, glyphs: 20), segment(700, 11.04, glyphs: 20),
                       segment(700, 9, glyphs: 30)])
        XCTAssertEqual(metrics[0]?.size, 11)
    }

    // MARK: - Deciding whether the fast reading can be trusted

    func testCoverageCountsTheLinesThatFoundASize() {
        let metrics: [PDFLineMetrics.Metric?] = [
            PDFLineMetrics.Metric(size: 11, bold: false), nil,
            PDFLineMetrics.Metric(size: 11, bold: false), nil,
        ]
        XCTAssertEqual(PDFLineMetrics.coverage(metrics), 0.5)
    }

    func testCoverageOfNothingIsZeroRatherThanACrash() {
        XCTAssertEqual(PDFLineMetrics.coverage([]), 0)
    }

    func testAFullyMatchedPageIsAboveTheFloor() {
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 700, size: 11), line(baseline: 680, size: 11)],
            segments: [segment(700, 11), segment(680, 11)])
        XCTAssertGreaterThan(PDFLineMetrics.coverage(metrics), PDFLineMetrics.coverageFloor)
    }

    func testAHalfReadPageFallsUnderTheFloor() {
        let metrics = PDFLineMetrics.match(
            lines: [line(baseline: 700, size: 11), line(baseline: 300, size: 11)],
            segments: [segment(700, 11)])
        XCTAssertLessThan(PDFLineMetrics.coverage(metrics), PDFLineMetrics.coverageFloor)
    }

    // MARK: - Weight out of the font name

    func testTheNameSaysBold() {
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "Helvetica-Bold"))
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "ArialMT,Bold"))
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "Inter-SemiBold"))
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "SFPro-Heavy"))
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "Roboto-Black"))
    }

    func testASubsetPrefixIsNotPartOfTheName() {
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "AAAAAB+Inter-Bold"))
        XCTAssertFalse(PDFLineMetrics.isBold(fontName: "BOLDAA+Inter-Regular"))
    }

    func testTheTerseSuffixCountsToo() {
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "Times,B"))
        XCTAssertTrue(PDFLineMetrics.isBold(fontName: "Times-B"))
    }

    func testOrdinaryFacesAreNotBold() {
        XCTAssertFalse(PDFLineMetrics.isBold(fontName: "Helvetica"))
        XCTAssertFalse(PDFLineMetrics.isBold(fontName: "TimesNewRomanPSMT"))
        XCTAssertFalse(PDFLineMetrics.isBold(fontName: "Inter-Regular"))
        XCTAssertFalse(PDFLineMetrics.isBold(fontName: ""))
    }
}
