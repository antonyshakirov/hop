import AppKit
import XCTest
@testable import Hop

@MainActor
final class PanelDismissalTests: XCTestCase {
    private let panel = NSRect(x: 100, y: 100, width: 360, height: 500)

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
