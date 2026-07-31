import XCTest
@testable import HopCore

/// Telling a live tunnel from one the system still calls connected. The readings
/// are what an interface's packet counters look like from `getifaddrs`, two
/// seconds apart — the cadence the module actually samples at.
final class TunnelLivenessTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testTheFirstReadingIsABaselineAndNeverAVerdict() {
        var watch = TunnelLiveness()
        // a huge count, but nothing to compare it against yet
        XCTAssertFalse(watch.observe(.init(inPackets: 0, outPackets: 90_000, at: at(0))))
        XCTAssertFalse(watch.isStalled)
    }

    func testTrafficBothWaysIsNeverCalledStalled() {
        var watch = TunnelLiveness()
        var inPackets: UInt64 = 0
        var outPackets: UInt64 = 0
        for step in 0...20 {
            watch.observe(.init(inPackets: inPackets, outPackets: outPackets,
                                at: at(Double(step) * 2)))
            inPackets += 300
            outPackets += 120
        }
        XCTAssertFalse(watch.isStalled)
    }

    func testOneSidedTrafficIsCalledStalledOnceTheSilenceIsLongEnough() {
        var watch = TunnelLiveness()
        watch.observe(.init(inPackets: 500, outPackets: 500, at: at(0)))
        // something is asking and nothing is coming back
        XCTAssertFalse(watch.observe(.init(inPackets: 500, outPackets: 508, at: at(2))))
        XCTAssertFalse(watch.observe(.init(inPackets: 500, outPackets: 516, at: at(4))))
        XCTAssertTrue(watch.observe(.init(inPackets: 500, outPackets: 524, at: at(6))))
        XCTAssertTrue(watch.isStalled)
    }

    func testAnIdleMacIsNotAccusedOfAnything() {
        var watch = TunnelLiveness()
        // nobody is asking for anything: a lone packet every half-minute is the
        // tunnel breathing, not the tunnel dying
        var outPackets: UInt64 = 500
        for step in 0...30 {
            watch.observe(.init(inPackets: 500, outPackets: outPackets, at: at(Double(step) * 2)))
            if step % 15 == 14 { outPackets += 1 }
        }
        XCTAssertFalse(watch.isStalled)
    }

    func testOneReturningPacketForgivesTheTunnelOnTheSpot() {
        var watch = TunnelLiveness()
        watch.observe(.init(inPackets: 500, outPackets: 500, at: at(0)))
        watch.observe(.init(inPackets: 500, outPackets: 540, at: at(6)))
        XCTAssertTrue(watch.isStalled)
        // the very sample that carries the packet clears the verdict
        XCTAssertFalse(watch.observe(.init(inPackets: 501, outPackets: 544, at: at(8))))
        XCTAssertFalse(watch.isStalled)
    }

    func testAConnectionThatKeepsDroppingAndReturningNeverGoesOrange() {
        var watch = TunnelLiveness()
        var inPackets: UInt64 = 0
        var outPackets: UInt64 = 0
        // four seconds of silence, then an answer, over and over: the light must
        // sit still through it rather than blink
        for step in 0...30 {
            watch.observe(.init(inPackets: inPackets, outPackets: outPackets,
                                at: at(Double(step) * 2)))
            XCTAssertFalse(watch.isStalled)
            outPackets += 30
            if step % 3 == 2 { inPackets += 12 }
        }
    }

    func testSilenceAloneIsNotEnoughWithoutSomethingAsking() {
        var watch = TunnelLiveness()
        watch.observe(.init(inPackets: 500, outPackets: 500, at: at(0)))
        // a full minute of nothing in either direction
        XCTAssertFalse(watch.observe(.init(inPackets: 500, outPackets: 500, at: at(60))))
        XCTAssertFalse(watch.isStalled)
    }

    func testTwoPacketsOutAreNotEnoughToAccuse() {
        var watch = TunnelLiveness()
        watch.observe(.init(inPackets: 500, outPackets: 500, at: at(0)))
        XCTAssertFalse(watch.observe(.init(inPackets: 500, outPackets: 502, at: at(30))))
        // the third one crosses the floor
        XCTAssertTrue(watch.observe(.init(inPackets: 500, outPackets: 503, at: at(32))))
    }

    func testACounterThatGoesBackwardsIsNotEvidenceAgainstTheTunnel() {
        var watch = TunnelLiveness()
        watch.observe(.init(inPackets: 4_294_000_000, outPackets: 4_294_000_000, at: at(0)))
        watch.observe(.init(inPackets: 4_294_000_000, outPackets: 4_294_000_050, at: at(6)))
        XCTAssertTrue(watch.isStalled)
        // the 32-bit value rolls over, or the interface was replaced under the
        // same name: a smaller number is not a verdict
        XCTAssertFalse(watch.observe(.init(inPackets: 10, outPackets: 20, at: at(8))))
        XCTAssertFalse(watch.isStalled)
    }

    func testTheVerdictSurvivesUntilSomethingComesBack() {
        var watch = TunnelLiveness()
        watch.observe(.init(inPackets: 500, outPackets: 500, at: at(0)))
        XCTAssertTrue(watch.observe(.init(inPackets: 500, outPackets: 540, at: at(6))))
        for step in 4...10 {
            XCTAssertTrue(watch.observe(.init(inPackets: 500,
                                              outPackets: UInt64(540 + step * 5),
                                              at: at(Double(step) * 2))))
        }
    }
}
