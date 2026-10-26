import AppKit
import XCTest
@testable import Hop

@MainActor
final class PanelPopoverSizingTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []

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

    func testTallContentClampAlsoFitsTheMeasuredWholePopoverInItsViewport() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first, "A native display is required to measure popover chrome")
        let availableHeight = min(CGFloat(600), screen.visibleFrame.height - 80)
        XCTAssertGreaterThan(availableHeight, 200)
        let desired = PanelHeightLimit.clamp(NSSize(width: 368, height: 1200),
                                            screenVisibleHeight: availableHeight)
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(origin: .zero, size: desired))
        let anchorWindow = NSWindow(contentRect: NSRect(x: screen.visibleFrame.midX,
            y: screen.visibleFrame.maxY - 24, width: 40, height: 20),
            styleMask: .borderless, backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        anchorWindow.contentView = anchor
        let popover = NSPopover()
        popover.animates = false
        popover.contentViewController = controller
        defer {
            popover.close(); anchorWindow.orderOut(nil)
            Self.retainedFixtures.append(contentsOf: [controller, anchorWindow, popover])
        }
        anchorWindow.orderFront(nil)
        PanelPopoverSizing.apply(desired, to: popover)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let frame = try XCTUnwrap(controller.view.window?.frame, "The native popover must produce a window")
        XCTAssertTrue(popover.isShown)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertEqual(popover.contentSize.height, desired.height, accuracy: 0.5)
        let measuredChrome = frame.height - popover.contentSize.height
        XCTAssertGreaterThan(measuredChrome, 0)
        XCTAssertLessThanOrEqual(frame.height, availableHeight,
            "Whole popover \(frame.height) must fit viewport \(availableHeight); content \(popover.contentSize.height), native chrome \(measuredChrome)")
    }
}
