import XCTest
@testable import HopCore

/// The 8-hour overrun banner's episode state machine: an episode begins the
/// moment a continuous run crosses 8 hours; acknowledging it suppresses the
/// banner for THAT run only; stopping and starting again (a new run = a new
/// start instant) that later crosses 8 hours is a fresh episode.
final class TrackerOverrunTests: XCTestCase {

    private let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private func plus(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    func testThresholdIsEightHours() {
        XCTAssertEqual(TrackerOverrun.threshold, 8 * 3600)
    }

    func testHiddenWhenNoActiveRun() {
        XCTAssertFalse(TrackerOverrun.isBannerVisible(
            activeStart: nil, now: plus(99_999), acknowledged: nil))
    }

    func testHiddenWhileRunIsUnderEightHours() {
        // one second short of the threshold — no episode yet
        XCTAssertFalse(TrackerOverrun.isBannerVisible(
            activeStart: base, now: plus(8 * 3600 - 1), acknowledged: nil))
    }

    func testHiddenExactlyAtEightHours() {
        // strictly greater — the boundary itself is not an overrun
        XCTAssertFalse(TrackerOverrun.isBannerVisible(
            activeStart: base, now: plus(8 * 3600), acknowledged: nil))
    }

    func testVisibleOnceRunPassesEightHours() {
        XCTAssertTrue(TrackerOverrun.isBannerVisible(
            activeStart: base, now: plus(8 * 3600 + 1), acknowledged: nil))
    }

    func testAcknowledgingThisRunSuppressesTheBanner() {
        // ack carries the SAME start instant → suppressed for the rest of the run
        XCTAssertFalse(TrackerOverrun.isBannerVisible(
            activeStart: base, now: plus(9 * 3600), acknowledged: base))
    }

    func testAcknowledgingStaysSuppressedAsTheRunGrows() {
        // still the same run hours later — no re-appearance
        XCTAssertFalse(TrackerOverrun.isBannerVisible(
            activeStart: base, now: plus(20 * 3600), acknowledged: base))
    }

    func testNewRunAfterAcknowledgedOneIsAFreshEpisode() {
        // the previous run was acknowledged; a NEW run (different start) crosses
        // 8h → the stale ack must not suppress it
        let newRun = plus(50 * 3600)
        XCTAssertTrue(TrackerOverrun.isBannerVisible(
            activeStart: newRun,
            now: newRun.addingTimeInterval(8 * 3600 + 1),
            acknowledged: base))
    }

    func testSameRunMatchesWithinTolerance() {
        // one side round-trips through UserDefaults as a Double — a hair of
        // drift must still read as the same run
        let a = Date(timeIntervalSinceReferenceDate: 123_456.7)
        let b = Date(timeIntervalSinceReferenceDate: 123_456.7 + 0.1)
        XCTAssertTrue(TrackerOverrun.isSameRun(a, b))
    }

    func testDistinctRunsDoNotMatch() {
        XCTAssertFalse(TrackerOverrun.isSameRun(base, plus(5)))
    }
}
