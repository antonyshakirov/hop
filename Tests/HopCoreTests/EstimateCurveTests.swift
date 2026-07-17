import XCTest
@testable import HopCore

final class EstimateCurveTests: XCTestCase {
    private func curve(
        points: [Int: Int64], sampleBytes: Int64 = 1_000, totalBytes: Int64 = 10_000
    ) -> EstimateCurve {
        EstimateCurve(
            samplePath: "/tmp/sample.jpg", format: "jpeg", scale: 1.0,
            totalBytes: totalBytes, sampleBytes: sampleBytes, points: points
        )
    }

    func testReferencePointIsExact() {
        let c = curve(points: [10: 100, 55: 400, 100: 900])
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 55), 400)
    }

    func testMidwayIsLinear() {
        let c = curve(points: [10: 100, 55: 400, 100: 900])
        // halfway between 55 and 100 → halfway between 400 and 900
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 78), 400 + 500 * 23 / 45, accuracy: 0.5)
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 32), 100 + 300 * 22 / 45, accuracy: 0.5)
    }

    func testOutsideRangeClampsToEdges() {
        let c = curve(points: [10: 100, 100: 900])
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 0), 100)
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 5), 100)
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 100), 900)
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 200), 900)
    }

    func testEmptyCurveHasNoProjection() {
        let c = curve(points: [:])
        XCTAssertEqual(c.sampleOutputBytes(atQuality: 55), 0)
        XCTAssertNil(c.projectedTotal(atQuality: 55))
        XCTAssertEqual(c.ratio(atQuality: 55), 0)
    }

    func testRatioIsOutputOverInput() {
        let c = curve(points: [55: 400], sampleBytes: 1_000)
        XCTAssertEqual(c.ratio(atQuality: 55), 0.4, accuracy: 0.0001)
    }

    func testProjectedTotalScalesGroupBysampleRatio() {
        // the sample compresses to 40% → the whole group is projected at 40%
        let c = curve(points: [55: 400], sampleBytes: 1_000, totalBytes: 50_000)
        XCTAssertEqual(c.projectedTotal(atQuality: 55), 20_000)
    }

    func testZeroSampleBytesMeansNoVerdict() {
        let c = curve(points: [55: 400], sampleBytes: 0)
        XCTAssertEqual(c.ratio(atQuality: 55), 0)
        XCTAssertNil(c.projectedTotal(atQuality: 55))
    }

    // MARK: - SizeFormatting

    func testSizeTextUsesDecimalUnitsLikeFinder() {
        XCTAssertEqual(SizeFormatting.sizeText(12_000), "12 KB")
        XCTAssertEqual(SizeFormatting.sizeText(999_000), "999 KB")
        XCTAssertEqual(SizeFormatting.sizeText(1_500_000), "1.5 MB")
        XCTAssertEqual(SizeFormatting.sizeText(2_300_000_000), "2.3 GB")
    }
}
