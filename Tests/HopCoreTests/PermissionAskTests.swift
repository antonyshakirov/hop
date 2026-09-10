import XCTest
@testable import HopCore

/// Pressing "start" on the drawing layer twice ran `tccutil reset` twice, and
/// the second reset threw away whatever the first had let the user decide —
/// with no dialog on screen to show that anything had been asked at all.
final class PermissionAskTests: XCTestCase {

    func testHopsRowIsDroppedOnlyOnTheFirstAskOfARun() {
        for trigger in PermissionAsk.Trigger.allCases {
            XCTAssertEqual(PermissionAsk.plan(trigger, askedThisRun: false, droppedThisRun: false)?.dropsTheRow,
                           true, "\(trigger)")
            XCTAssertNotEqual(PermissionAsk.plan(trigger, askedThisRun: true, droppedThisRun: true)?.dropsTheRow,
                              true, "\(trigger)")
        }
    }

    func testAFeatureStoppedByTheMissingPermissionAsksOncePerRun() {
        let first = PermissionAsk.plan(.featureStopped, askedThisRun: false, droppedThisRun: false)
        XCTAssertEqual(first, PermissionAsk.Plan(dropsTheRow: true, requests: true, opens: nil))
        XCTAssertNil(PermissionAsk.plan(.featureStopped, askedThisRun: true, droppedThisRun: true))
    }

    func testAModuleThatReadsTheScreenOpensThePermissionsPageEveryTime() {
        let first = PermissionAsk.plan(.screenModule, askedThisRun: false, droppedThisRun: false)
        XCTAssertEqual(first, PermissionAsk.Plan(dropsTheRow: true, requests: true, opens: .permissionsPage))
        let again = PermissionAsk.plan(.screenModule, askedThisRun: true, droppedThisRun: true)
        XCTAssertEqual(again, PermissionAsk.Plan(dropsTheRow: false, requests: true, opens: .permissionsPage))
    }

    /// Once Hop's row has been dropped and asked for, the switch is in System
    /// Settings, and a request would only pull Hop back in front of it.
    func testAButtonGoesToSystemSettingsOnceTheRowHasBeenDropped() {
        let first = PermissionAsk.plan(.button, askedThisRun: false, droppedThisRun: false)
        XCTAssertEqual(first, PermissionAsk.Plan(dropsTheRow: true, requests: true, opens: nil))
        let again = PermissionAsk.plan(.button, askedThisRun: true, droppedThisRun: true)
        XCTAssertEqual(again, PermissionAsk.Plan(dropsTheRow: false, requests: false, opens: .systemSettings))
    }
}
