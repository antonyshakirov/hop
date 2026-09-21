import XCTest
@testable import HopCore

final class SpeedSummaryTests: XCTestCase {
    /// What the tool prints one direction at a time (`-s`), which is how Hop
    /// runs it: two responsiveness lines and no single "Responsiveness:".
    private let sequential = """
    ==== SUMMARY ====
    Uplink capacity: 211.154 Mbps
    Downlink capacity: 456.270 Mbps
    Uplink Responsiveness: Medium (159.134 milliseconds | 377 RPM)
    Downlink Responsiveness: High (54.031 milliseconds | 1110 RPM)
    Idle Latency: 17.047 milliseconds | 3519 RPM
    """

    /// What it printed while both directions ran at once.
    private let parallel = """
    ==== SUMMARY ====
    Uplink capacity: 77.542 Mbps
    Downlink capacity: 478.115 Mbps
    Responsiveness: Medium (107.135 milliseconds | 560 RPM)
    Idle Latency: 17.047 milliseconds | 3519 RPM
    """

    func testReadsBothCapacities() {
        let result = SpeedSummary.parse(sequential)
        XCTAssertEqual(result?.down, 456.270)
        XCTAssertEqual(result?.up, 211.154)
    }

    func testTakesTheWorseOfTheTwoResponsivenessScores() {
        // 377 is the number that describes the call that stutters; the idle
        // latency line below it carries an RPM too and must not be mistaken for
        // either of them.
        XCTAssertEqual(SpeedSummary.parse(sequential)?.rpm, 377)
    }

    func testStillReadsTheSingleScoreOfAParallelRun() {
        XCTAssertEqual(SpeedSummary.parse(parallel)?.rpm, 560)
    }

    func testARunWithoutBothCapacitiesHasNoResult() {
        XCTAssertNil(SpeedSummary.parse("==== SUMMARY ====\nUplink capacity: 1.0 Mbps"))
        XCTAssertNil(SpeedSummary.parse(""))
    }

    func testAMissingScoreIsZeroRatherThanNoResult() {
        let text = "Uplink capacity: 1.5 Mbps\nDownlink capacity: 9.5 Mbps"
        XCTAssertEqual(SpeedSummary.parse(text), SpeedSummary.Result(down: 9.5, up: 1.5, rpm: 0))
    }

    func testLiveLinesGiveTheLatestReading() {
        // the tool redraws its line over itself, so every reading is in the text
        let stream = "Downlink: 141.737 Mbps, 0 RPM - Uplink: 0.000 Mbps, 0 RPM"
            + "Downlink: 308.077 Mbps, 0 RPM - Uplink: 0.000 Mbps, 0 RPM"
        XCTAssertEqual(SpeedSummary.lastNumber(in: stream, after: "Downlink:"), 308.077)
        XCTAssertEqual(SpeedSummary.lastNumber(in: stream, after: "Uplink:"), 0)
    }
}
