import AppKit
import XCTest
@testable import Hop

@MainActor
final class HandCursorAreaTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    func testControlRebuildRepairsATextCursorResolvedLaterByAppKit() {
        fixture { area, _ in
            area.updateTrackingAreas()
            NSCursor.iBeam.set()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
        }
    }

    func testHiddenControlCannotReplaceAnotherViewsCursor() {
        fixture { area, window in
            window.orderOut(nil)
            NSCursor.iBeam.set()
            area.recheck()
            XCTAssertEqual(NSCursor.current, NSCursor.iBeam)
        }
    }

    func testCoveredControlCannotReplaceAnotherWindowsCursor() {
        fixture { area, window in
            let cover = NSWindow(contentRect: window.frame, styleMask: .borderless,
                backing: .buffered, defer: false)
            cover.isReleasedWhenClosed = false
            cover.level = .screenSaver
            cover.orderFrontRegardless()
            cover.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            defer {
                cover.orderOut(nil)
                Self.retainedWindows.append(cover)
            }
            NSCursor.iBeam.set()
            area.recheck()
            XCTAssertEqual(NSCursor.current, NSCursor.iBeam)
        }
    }

    func testDisabledControlUsesArrowAndCanBecomeClickableWithoutPointerMovement() {
        fixture { area, _ in
            area.isEnabled = false
            area.recheck()
            XCTAssertEqual(NSCursor.current, NSCursor.arrow)
            area.isEnabled = true
            area.refreshCursor()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(NSCursor.current, NSCursor.pointingHand)
        }
    }

    func testExitDoesNotOverwriteTheCursorChosenByTheNextControl() throws {
        try fixture { area, window in
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0))
            NSCursor.iBeam.set()
            area.mouseExited(with: event)
            XCTAssertEqual(NSCursor.current, NSCursor.iBeam)
        }
    }

    private func fixture(_ body: (HandCursorArea.Area, NSWindow) throws -> Void) rethrows {
        _ = NSApplication.shared
        let previous = NSCursor.current, point = NSEvent.mouseLocation
        let window = NSWindow(contentRect: NSRect(x: point.x - 40, y: point.y - 15,
            width: 120, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        let area = HandCursorArea.Area(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        window.contentView = area
        window.orderFrontRegardless()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        defer {
            window.orderOut(nil)
            previous.set()
            Self.retainedWindows.append(window)
        }
        try body(area, window)
    }
}
