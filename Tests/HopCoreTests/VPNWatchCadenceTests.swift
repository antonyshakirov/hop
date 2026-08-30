import XCTest
@testable import HopCore

/// What the VPN module does between announcements, and what an announcement
/// makes it do.
final class VPNWatchCadenceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func decide(panelOpen: Bool = false, tracking: Bool = false, vanished: Bool = false,
                        lastChange: Date? = nil, readAgo: TimeInterval = 0) -> VPNWatchCadence {
        VPNWatchCadence.decide(panelOpen: panelOpen, tracking: tracking, vanished: vanished,
                               lastChange: lastChange,
                               lastListRead: now.addingTimeInterval(-readAgo), now: now)
    }

    // MARK: - Resting

    func testIdlesWithNothingConnectedAndNothingOnScreen() {
        let plan = decide()
        XCTAssertEqual(plan.interval, VPNWatchCadence.idleInterval)
        XCTAssertFalse(plan.readsList)
    }

    func testTheIdleFloorStillReadsTheListEventually() {
        XCTAssertTrue(decide(readAgo: VPNWatchCadence.idleInterval).readsList)
    }

    func testATunnelUpIsMeasuredEveryFewSecondsWithoutRereadingTheList() {
        let plan = decide(tracking: true, readAgo: 4)
        XCTAssertEqual(plan.interval, VPNWatchCadence.watchInterval)
        XCTAssertFalse(plan.readsList)
    }

    func testTheOpenPanelReadsTheListEveryTick() {
        let plan = decide(panelOpen: true)
        XCTAssertEqual(plan.interval, VPNWatchCadence.watchInterval)
        XCTAssertTrue(plan.readsList)
    }

    /// Free to learn and unambiguous: the list is already out of date.
    func testAVanishedInterfaceReadsTheListAheadOfTheFloor() {
        XCTAssertTrue(decide(tracking: true, vanished: true).readsList)
    }

    // MARK: - After an announcement

    func testAnAnnouncementReadsTheListAndSpeedsUp() {
        let plan = decide(lastChange: now)
        XCTAssertEqual(plan.interval, VPNWatchCadence.burstInterval)
        XCTAssertTrue(plan.readsList)
    }

    /// The point of the window: the signal precedes the tunnel, so the module has
    /// to keep looking after it rather than read once and settle.
    func testTheWindowKeepsReadingUntilItRunsOut() {
        let inside = decide(lastChange: now.addingTimeInterval(-(VPNWatchCadence.burst - 1)))
        XCTAssertEqual(inside.interval, VPNWatchCadence.burstInterval)
        XCTAssertTrue(inside.readsList)
    }

    func testTheWindowRunsOutAndTheModuleSettlesBack() {
        let after = decide(lastChange: now.addingTimeInterval(-VPNWatchCadence.burst))
        XCTAssertEqual(after.interval, VPNWatchCadence.idleInterval)
        XCTAssertFalse(after.readsList)
    }

    func testTheWindowSettlesBackToWatchingWhileATunnelIsUp() {
        let after = decide(tracking: true, lastChange: now.addingTimeInterval(-VPNWatchCadence.burst))
        XCTAssertEqual(after.interval, VPNWatchCadence.watchInterval)
    }

    // MARK: - Announcements arriving together

    /// A tunnel coming up moves several keys at once, each arriving on its own.
    func testASecondAnnouncementRidesOnTheFirstOnesReading() {
        XCTAssertFalse(VPNWatchCadence.worthReading(
            lastListRead: now.addingTimeInterval(-VPNWatchCadence.coalesce / 2), now: now))
    }

    func testAnAnnouncementAfterAQuietMomentEarnsItsOwnReading() {
        XCTAssertTrue(VPNWatchCadence.worthReading(
            lastListRead: now.addingTimeInterval(-1), now: now))
    }

    // MARK: - The shape of the whole thing

    /// The announcement has to beat the old behaviour by enough to be worth the
    /// machinery, and the floor has to stay behind it.
    func testTheWindowIsFasterThanTheFloorByAnOrderOfMagnitude() {
        XCTAssertLessThan(VPNWatchCadence.burstInterval * 10, VPNWatchCadence.idleInterval)
        XCTAssertLessThan(VPNWatchCadence.burst, VPNWatchCadence.idleInterval)
    }
}
