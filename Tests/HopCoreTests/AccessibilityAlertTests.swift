import XCTest
@testable import HopCore

/// What the panel owes the user about accessibility, and what the watchdog does
/// under a live keyboard lock.
final class AccessibilityAlertTests: XCTestCase {

    // MARK: - The alert

    func testNothingIsOwedWhileThePermissionWorks() {
        XCTAssertEqual(
            AccessibilityVerdict.alert(granted: true, wasGrantedBefore: true,
                                       suppressionProven: true),
            .none)
    }

    func testAPermissionNeverGivenIsMissing() {
        XCTAssertEqual(
            AccessibilityVerdict.alert(granted: false, wasGrantedBefore: false,
                                       suppressionProven: nil),
            .missing)
    }

    func testAPermissionThatUsedToWorkIsLost() {
        XCTAssertEqual(
            AccessibilityVerdict.alert(granted: false, wasGrantedBefore: true,
                                       suppressionProven: nil),
            .lost)
    }

    func testATrustedProcessThatSuppressesNothingIsStale() {
        XCTAssertEqual(
            AccessibilityVerdict.alert(granted: true, wasGrantedBefore: true,
                                       suppressionProven: false),
            .stale)
    }

    func testAnUnmeasuredPermissionIsNotCalledStale() {
        XCTAssertEqual(
            AccessibilityVerdict.alert(granted: true, wasGrantedBefore: false,
                                       suppressionProven: nil),
            .none)
    }

    func testARefusalOutranksAnOldMeasurement() {
        XCTAssertEqual(
            AccessibilityVerdict.alert(granted: false, wasGrantedBefore: true,
                                       suppressionProven: false),
            .lost)
    }

    // MARK: - Whether the panel carries it

    func testAWorkingPermissionCarriesNoBanner() {
        XCTAssertFalse(AccessibilityVerdict.showsBanner(.none, featureWasBlocked: true))
    }

    func testAPermissionNeverNeededIsNotAnnounced() {
        XCTAssertFalse(AccessibilityVerdict.showsBanner(.missing, featureWasBlocked: false))
    }

    func testAMissingPermissionIsAnnouncedOnceItStopsSomething() {
        XCTAssertTrue(AccessibilityVerdict.showsBanner(.missing, featureWasBlocked: true))
    }

    func testAPermissionTakenAwayIsAnnouncedWithoutWaiting() {
        XCTAssertTrue(AccessibilityVerdict.showsBanner(.lost, featureWasBlocked: false))
        XCTAssertTrue(AccessibilityVerdict.showsBanner(.stale, featureWasBlocked: false))
    }

    // MARK: - The watchdog

    func testALiveTapIsLeftAlone() {
        XCTAssertEqual(TapWatchdog.step(tapEnabled: true, reArmedLastTick: false), .fine)
        XCTAssertEqual(TapWatchdog.step(tapEnabled: true, reArmedLastTick: true), .fine)
    }

    func testATapFoundOffIsArmedAgain() {
        XCTAssertEqual(TapWatchdog.step(tapEnabled: false, reArmedLastTick: false), .reArm)
    }

    func testATapThatStaysOffAfterBeingArmedEndsTheLock() {
        XCTAssertEqual(TapWatchdog.step(tapEnabled: false, reArmedLastTick: true), .giveUp)
    }
}
