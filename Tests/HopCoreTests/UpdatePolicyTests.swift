import XCTest
@testable import HopCore

final class UpdatePolicyTests: XCTestCase {
    private let threshold: TimeInterval = 20 * 60

    /// A fully idle machine: past the quiet window, nothing running.
    private func canInstall(
        critical: Bool = false,
        timerBusy: Bool = false,
        keepAwakeActive: Bool = false,
        panelOpen: Bool = false,
        converterBusy: Bool = false,
        secondsSinceInteraction: TimeInterval = 20 * 60
    ) -> Bool {
        UpdateInstallPolicy.canInstall(
            critical: critical,
            timerBusy: timerBusy,
            keepAwakeActive: keepAwakeActive,
            panelOpen: panelOpen,
            converterBusy: converterBusy,
            secondsSinceInteraction: secondsSinceInteraction,
            idleThreshold: threshold
        )
    }

    // MARK: - install allowed

    func testIdleUnusedMachineInstalls() {
        XCTAssertTrue(canInstall())
    }

    func testInstallsExactlyAtThreshold() {
        XCTAssertTrue(canInstall(secondsSinceInteraction: threshold))
    }

    // MARK: - non-critical blockers

    func testRecentInteractionBlocks() {
        XCTAssertFalse(canInstall(secondsSinceInteraction: threshold - 1))
        XCTAssertFalse(canInstall(secondsSinceInteraction: 0))
    }

    func testKeepAwakeBlocks() {
        XCTAssertFalse(canInstall(keepAwakeActive: true))
    }

    func testOpenPanelBlocks() {
        XCTAssertFalse(canInstall(panelOpen: true))
    }

    func testActiveConversionBlocks() {
        XCTAssertFalse(canInstall(converterBusy: true))
    }

    // MARK: - the timer is sacred, even for critical

    func testRunningTimerBlocksNonCritical() {
        XCTAssertFalse(canInstall(timerBusy: true))
    }

    func testRunningTimerBlocksEvenCritical() {
        XCTAssertFalse(canInstall(critical: true, timerBusy: true))
    }

    // MARK: - critical bypasses the soft blockers

    func testCriticalIgnoresRecentUseAwakePanelConverter() {
        XCTAssertTrue(canInstall(
            critical: true,
            keepAwakeActive: true,
            panelOpen: true,
            converterBusy: true,
            secondsSinceInteraction: 0
        ))
    }

    // MARK: - ActivityTracker

    func testTrackerStartsIdle() {
        let t = ActivityTracker()
        // .distantPast → an enormous idle age, well past any threshold
        XCTAssertGreaterThan(t.secondsSinceInteraction(now: Date(timeIntervalSince1970: 0)), threshold)
    }

    func testNoteResetsIdleAge() {
        let t = ActivityTracker()
        let now = Date(timeIntervalSince1970: 10_000)
        t.note(at: now)
        XCTAssertEqual(t.secondsSinceInteraction(now: now), 0, accuracy: 0.001)
        XCTAssertEqual(t.secondsSinceInteraction(now: now.addingTimeInterval(300)), 300, accuracy: 0.001)
    }

    func testNoteNeverMovesStampBackwards() {
        let t = ActivityTracker()
        let later = Date(timeIntervalSince1970: 10_000)
        t.note(at: later)
        t.note(at: later.addingTimeInterval(-500)) // stale, out-of-order event
        // still measured from the later stamp, not the earlier one
        XCTAssertEqual(t.secondsSinceInteraction(now: later), 0, accuracy: 0.001)
    }
}
