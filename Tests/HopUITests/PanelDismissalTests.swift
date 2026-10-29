import AppKit
import XCTest
@testable import Hop

@MainActor
final class PanelDismissalTests: XCTestCase {
    private let panel = NSRect(x: 100, y: 100, width: 360, height: 500)

    func testStatusButtonMouseDownLeavesThePanelForItsMouseUpToggle() {
        XCTAssertFalse(StatusItemController.shouldClosePopover(
            pointer: NSPoint(x: 180, y: 625), panelFrame: panel, explicit: false,
            statusButtonFrame: NSRect(x: 160, y: 610, width: 40, height: 24)))
    }

    func testExplicitIconToggleCanCloseAboveThePanel() {
        XCTAssertTrue(StatusItemController.shouldClosePopover(
            pointer: NSPoint(x: 180, y: 625), panelFrame: panel, explicit: true,
            statusButtonFrame: NSRect(x: 160, y: 610, width: 40, height: 24)))
    }

    func testTabClickInsidePanelCannotDismissIt() {
        XCTAssertFalse(StatusItemController.shouldClosePopover(
            pointer: NSPoint(x: 180, y: 570), panelFrame: panel, explicit: false))
    }

    func testClickOutsideStillDismissesPanel() {
        XCTAssertTrue(StatusItemController.shouldClosePopover(
            pointer: NSPoint(x: 90, y: 570), panelFrame: panel, explicit: false))
    }

    func testExplicitCloseWorksEvenWithPointerInside() {
        XCTAssertTrue(StatusItemController.shouldClosePopover(
            pointer: NSPoint(x: 180, y: 570), panelFrame: panel, explicit: true))
    }

    func testEscapeCanCloseWhilePointerIsInside() {
        XCTAssertTrue(StatusItemController.shouldClosePopover(
            pointer: NSPoint(x: 180, y: 570), panelFrame: panel,
            explicit: false, keyboardEvent: true))
    }
}
