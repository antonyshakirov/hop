import AppKit
import XCTest
@testable import Hop

@MainActor
final class PanelPopoverSizingTests: XCTestCase {
    func testRepeatedCompactMeasurementRepairsAHeightRestoredByAppKit() {
        let popover = NSPopover()
        let compact = NSSize(width: 368, height: 400)
        XCTAssertTrue(PanelPopoverSizing.apply(compact, to: popover))
        popover.contentSize = NSSize(width: 368, height: 800)
        XCTAssertTrue(PanelPopoverSizing.apply(compact, to: popover))
        XCTAssertEqual(popover.contentSize, compact)
    }

    func testCorrectActualHeightDoesNotResizeAgain() {
        let popover = NSPopover()
        let compact = NSSize(width: 368, height: 400)
        PanelPopoverSizing.apply(compact, to: popover)
        XCTAssertFalse(PanelPopoverSizing.apply(compact, to: popover))
    }
}
