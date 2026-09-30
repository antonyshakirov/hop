import AppKit
import XCTest
@testable import Hop

/// SPEC: docs/spec.md — "Hard invariants of the panel", a click never makes Hop the active app.
@MainActor
final class PanelActivationTests: XCTestCase {
    func testPanelWindowIsToldNotToActivateOnMacOS27() throws {
        guard #available(macOS 27.0, *) else { throw XCTSkip("the older path activates and yields") }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        XCTAssertTrue(StatusItemController.preventActivation(of: window))
        let getter = Selector(("_preventsActivation"))
        XCTAssertTrue(window.responds(to: getter))
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        XCTAssertTrue(unsafeBitCast(window.method(for: getter), to: Getter.self)(window, getter))
    }
}
