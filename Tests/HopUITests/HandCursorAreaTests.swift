import AppKit
import XCTest
@testable import Hop

@MainActor
final class HandCursorAreaTests: XCTestCase {
    private static var retainedWindows: [NSWindow] = []

    private final class Pointer {
        var visible = true
        var covered = false
        var location = NSPoint(x: 40, y: 15)
        var cursor = NSCursor.arrow
    }

    func testControlRebuildRepairsATextCursorResolvedLaterByAppKit() {
        fixture { area, _, pointer in
            area.updateTrackingAreas()
            pointer.cursor = .iBeam
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            XCTAssertEqual(pointer.cursor, NSCursor.pointingHand)
        }
    }

    func testHiddenControlCannotReplaceAnotherViewsCursor() {
        fixture { area, _, pointer in
            pointer.visible = false
            pointer.cursor = .iBeam
            area.recheck()
            XCTAssertEqual(pointer.cursor, NSCursor.iBeam)
        }
    }

    func testCoveredControlCannotReplaceAnotherWindowsCursor() {
        fixture { area, _, pointer in
            pointer.covered = true
            pointer.cursor = .iBeam
            area.recheck()
            XCTAssertEqual(pointer.cursor, NSCursor.iBeam)
        }
    }

    func testDisabledControlUsesArrowAndCanBecomeClickableWithoutPointerMovement() {
        fixture { area, _, pointer in
            area.isEnabled = false
            area.recheck()
            XCTAssertEqual(pointer.cursor, NSCursor.arrow)
            area.isEnabled = true
            area.refreshCursor()
            XCTAssertEqual(pointer.cursor, NSCursor.pointingHand)
        }
    }

    func testExitDoesNotOverwriteTheCursorChosenByTheNextControl() throws {
        try fixture { area, window, pointer in
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0))
            pointer.cursor = .iBeam
            area.mouseExited(with: event)
            XCTAssertEqual(pointer.cursor, NSCursor.iBeam)
        }
    }

    func testPointerOutsideControlCannotReplaceAnotherViewsCursor() {
        fixture { area, _, pointer in
            pointer.location = NSPoint(x: 200, y: 100)
            pointer.cursor = .iBeam
            area.recheck()
            XCTAssertEqual(pointer.cursor, .iBeam)
        }
    }

    private func fixture(_ body: (HandCursorArea.Area, NSWindow, Pointer) throws -> Void) rethrows {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let pointer = Pointer()
        let area = HandCursorArea.Area(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        area.pointerState = { window in
            .init(windowVisible: pointer.visible,
                  frontWindowNumber: window.windowNumber + (pointer.covered ? 1 : 0),
                  location: pointer.location)
        }
        area.setCursor = { pointer.cursor = $0 }
        window.contentView = area
        defer { Self.retainedWindows.append(window) }
        let initialRefresh = expectation(description: "Initial cursor refresh completed")
        DispatchQueue.main.async { initialRefresh.fulfill() }
        wait(for: [initialRefresh], timeout: 1)
        try body(area, window, pointer)
    }
}
