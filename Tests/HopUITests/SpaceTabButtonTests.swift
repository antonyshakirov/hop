import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class SpaceTabButtonTests: XCTestCase {
    // WORKAROUND: XCTest crashes while draining this synthetic window's
    // autorelease pool on macOS 26; keep the fixture until the process exits.
    private static var retainedFixtures: [AnyObject] = []

    func testInactivePanelTabAcceptsFirstClick() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: SpaceTabButton(icon: "star", active: false) {})
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                      location: NSPoint(x: 35, y: 40),
                                      modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 1, clickCount: 1, pressure: 1)!
        XCTAssertTrue(host.acceptsFirstMouse(for: event))
        Self.retainedFixtures.append(contentsOf: [window, host, event])
    }
}
