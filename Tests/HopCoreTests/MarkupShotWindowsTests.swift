import XCTest
@testable import HopCore

/// The panel blinked on every copy and save: it stepped out of the shot and came
/// back after the capture.
final class MarkupShotWindowsTests: XCTestCase {

    func testTheLayerStaysInTheShotAndTheRestOfHopIsLeftOut() {
        let shot = MarkupShotWindows(ours: [10, 20, 30, 40], layer: [10, 30], panel: 20)
        XCTAssertEqual(shot.leftOut, [20, 40])
    }

    func testAListedPanelStaysOnScreen() {
        let shot = MarkupShotWindows(ours: [10, 20], layer: [10], panel: 20)
        XCTAssertFalse(shot.panelStepsAside)
    }

    func testAPanelTheListDoesNotHaveStepsAside() {
        let shot = MarkupShotWindows(ours: [10], layer: [10], panel: 20)
        XCTAssertTrue(shot.panelStepsAside)
    }

    func testNoPanelHasNothingToMove() {
        let shot = MarkupShotWindows(ours: [10, 40], layer: [10], panel: nil)
        XCTAssertFalse(shot.panelStepsAside)
        XCTAssertEqual(shot.leftOut, [40])
    }
}
