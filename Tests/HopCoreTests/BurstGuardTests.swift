import XCTest
@testable import HopCore

final class BurstGuardTests: XCTestCase {
    private func guardUnderTest() -> BurstGuard {
        BurstGuard(limit: 3, window: 1, cooldown: 10)
    }

    func testAnOrdinaryRateIsAnswered() {
        var subject = guardUnderTest()
        for step in 0..<20 {
            XCTAssertTrue(subject.allows(at: Double(step)))
        }
    }

    func testABurstIsRefusedAndStaysRefusedForTheCooldown() {
        var subject = guardUnderTest()
        XCTAssertTrue(subject.allows(at: 100.0))
        XCTAssertTrue(subject.allows(at: 100.1))
        XCTAssertTrue(subject.allows(at: 100.2))
        XCTAssertFalse(subject.allows(at: 100.3)) // fourth inside one second
        XCTAssertFalse(subject.allows(at: 105.0))
        XCTAssertTrue(subject.isMuted(at: 109.9))
        XCTAssertFalse(subject.isMuted(at: 110.3))
        XCTAssertTrue(subject.allows(at: 110.3))
    }

    func testFiringsOlderThanTheWindowDoNotCount() {
        var subject = guardUnderTest()
        XCTAssertTrue(subject.allows(at: 0))
        XCTAssertTrue(subject.allows(at: 1.5))
        XCTAssertTrue(subject.allows(at: 3.0))
        XCTAssertTrue(subject.allows(at: 4.5))
    }

    func testTheReasonIsReportedOnceRatherThanEveryTime() {
        var subject = guardUnderTest()
        for stamp in [50.0, 50.1, 50.2] { _ = subject.allows(at: stamp) }
        XCTAssertEqual(subject.allowsAndReportsMuting(at: 50.3).muted, true)
        XCTAssertEqual(subject.allowsAndReportsMuting(at: 50.4).muted, false)
        XCTAssertEqual(subject.allowsAndReportsMuting(at: 55.0).muted, false)
    }

    func testTheCooldownStartsCleanRatherThanMutingAgainAtOnce() {
        var subject = guardUnderTest()
        for stamp in [0, 0.1, 0.2, 0.3] { _ = subject.allows(at: stamp) }
        XCTAssertTrue(subject.allows(at: 10.3))
        XCTAssertTrue(subject.allows(at: 10.4))
        XCTAssertTrue(subject.allows(at: 10.5))
    }
}
