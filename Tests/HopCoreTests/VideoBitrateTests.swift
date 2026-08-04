import XCTest
@testable import HopCore

final class VideoBitrateTests: XCTestCase {
    private func rate(
        _ width: Double, _ height: Double, fps: Double = 30,
        codec: VideoBitrate.Codec = .h264, quality: Double = 0.5
    ) -> Int {
        VideoBitrate.bitsPerSecond(width: width, height: height, fps: fps,
                                   codec: codec, quality: quality)
    }

    // MARK: - The dial

    func testTurningTheDialUpSpendsMoreBits() {
        let low = rate(1920, 1080, quality: 0.1)
        let middle = rate(1920, 1080, quality: 0.5)
        let high = rate(1920, 1080, quality: 1)
        XCTAssertLessThan(low, middle)
        XCTAssertLessThan(middle, high)
    }

    func testTheDialIsClampedRatherThanTrusted() {
        XCTAssertEqual(rate(1920, 1080, quality: -3), rate(1920, 1080, quality: 0))
        XCTAssertEqual(rate(1920, 1080, quality: 7), rate(1920, 1080, quality: 1))
    }

    func testEvenTheBottomOfTheDialStaysWatchable() {
        // a postage-stamp frame at the lowest setting still gets a floor
        XCTAssertGreaterThanOrEqual(rate(320, 240, quality: 0), 120_000)
    }

    // MARK: - What the numbers mean

    func testMorePixelsCostProportionallyMoreBits() {
        let small = rate(1280, 720)
        let large = rate(2560, 1440)
        // four times the pixels, four times the bitrate
        XCTAssertEqual(Double(large) / Double(small), 4, accuracy: 0.01)
    }

    func testDoublingTheFrameRateDoublesTheBitrate() {
        XCTAssertEqual(Double(rate(1920, 1080, fps: 60)) / Double(rate(1920, 1080, fps: 30)),
                       2, accuracy: 0.01)
    }

    func testHevcCarriesTheSamePictureInFewerBits() {
        let h264 = rate(1920, 1080, codec: .h264)
        let hevc = rate(1920, 1080, codec: .hevc)
        XCTAssertLessThan(hevc, h264)
        XCTAssertEqual(Double(hevc) / Double(h264), 0.65, accuracy: 0.01)
    }

    func testAFrameWithNoSizeHasNoBitrate() {
        XCTAssertEqual(rate(0, 1080), 0)
        XCTAssertEqual(rate(1920, 0), 0)
        XCTAssertEqual(rate(1920, 1080, fps: 0), 0)
    }

    // MARK: - The forecast

    func testTheForecastIsBitrateTimesDuration() {
        // 60 seconds at 8 Mbps video + 128 kbps audio ≈ 62 MB
        let bytes = VideoBitrate.projectedBytes(seconds: 60, videoBitsPerSecond: 8_000_000)
        XCTAssertEqual(Double(bytes), 62_200_000, accuracy: 1_500_000)
    }

    func testAClipOfNoLengthWeighsNothing() {
        XCTAssertEqual(VideoBitrate.projectedBytes(seconds: 0, videoBitsPerSecond: 8_000_000), 0)
    }

    func testAForecastHeavierThanTheSourceReportsTheSource() {
        // re-encoding an already-small file cannot be sold as a saving
        XCTAssertEqual(VideoBitrate.honestProjection(projected: 5_000_000, original: 3_300_000),
                       3_300_000)
        XCTAssertEqual(VideoBitrate.honestProjection(projected: 1_000_000, original: 3_300_000),
                       1_000_000)
    }

    func testWithNoSourceSizeTheProjectionStands() {
        XCTAssertEqual(VideoBitrate.honestProjection(projected: 1_000_000, original: 0), 1_000_000)
    }
}
