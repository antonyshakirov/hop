import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class ClipboardHoverControllerTests: XCTestCase {
    @MainActor private final class Clock {
        final class Entry {
            let due: Double
            let action: () -> Void
            var cancelled = false
            init(due: Double, action: @escaping () -> Void) { self.due = due; self.action = action }
        }
        var now = 0.0
        var entries: [Entry] = []
        func schedule(_ delay: Double, _ action: @escaping () -> Void) -> (() -> Void) {
            let entry = Entry(due: now + delay, action: action)
            entries.append(entry)
            return { entry.cancelled = true }
        }
        func advance(_ seconds: Double) {
            now += seconds
            for entry in entries where !entry.cancelled && entry.due <= now + 0.00001 {
                entry.cancelled = true; entry.action()
            }
        }
    }
    @MainActor private final class Fixture {
        let screen = NSRect(x: -10000, y: -10000, width: 800, height: 600)
        let clock = Clock()
        let parent: NSPanel = {
            _ = NSApplication.shared
            return NSPanel(contentRect: NSRect(x: -9800, y: -9600, width: 360, height: 120),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        }()
        let anchor = ClipboardHoverAnchorView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
        let controller: ClipboardHoverController
        init(text: String = "First paragraph\n\nDetailed second paragraph") {
            let clock = clock, screen = screen
            controller = ClipboardHoverController(schedule: { clock.schedule($0, $1) },
                containsPointer: { _ in true }, visibleFrame: { _ in screen })
            parent.isReleasedWhenClosed = false
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
            content.addSubview(anchor); parent.contentView = content
            anchor.controller = controller
            anchor.configure(id: UUID(), text: text, rtl: false)
            parent.orderFront(nil)
        }
        func finish() { controller.cancel(); parent.orderOut(nil); parent.close() }
        var displayedText: String? {
            (controller.panel?.contentView?.subviews.first as? NSTextField)?.stringValue
        }
    }

    func testHalfSecondDelayShowsActualTextWithoutFocusOrParentGeometryChange() {
        let fixture = Fixture(); defer { fixture.finish() }
        let frame = fixture.parent.frame, responder = fixture.parent.firstResponder, key = NSApp.keyWindow
        fixture.controller.request(from: fixture.anchor)
        fixture.clock.advance(0.49)
        XCTAssertNil(fixture.controller.panel)
        fixture.clock.advance(0.01)
        XCTAssertTrue(fixture.controller.panel?.isVisible == true)
        XCTAssertEqual(fixture.displayedText, fixture.anchor.previewText)
        XCTAssertTrue(fixture.controller.panel?.ignoresMouseEvents == true)
        XCTAssertFalse(fixture.controller.panel?.canBecomeKey ?? true)
        XCTAssertFalse(fixture.controller.panel?.canBecomeMain ?? true)
        XCTAssertEqual(fixture.parent.frame, frame)
        XCTAssertTrue(fixture.parent.firstResponder === responder)
        XCTAssertTrue(NSApp.keyWindow === key)
        XCTAssertTrue(fixture.controller.panel?.parent === fixture.parent)
    }

    func testMovementWithinRowDoesNotRestartItsDelayAndReentryWorksRepeatedly() {
        let fixture = Fixture(); defer { fixture.finish() }
        for _ in 0..<3 {
            fixture.controller.request(from: fixture.anchor)
            fixture.clock.advance(0.4)
            fixture.controller.request(from: fixture.anchor)
            fixture.clock.advance(0.1)
            XCTAssertTrue(fixture.controller.panel?.isVisible == true)
            fixture.anchor.cancelPreview()
            XCTAssertFalse(fixture.controller.panel?.isVisible ?? false)
        }
    }

    func testAnotherRowGetsANewDelayAndLateFirstRowExitCannotCancelIt() {
        let fixture = Fixture(); defer { fixture.finish() }
        let other = ClipboardHoverAnchorView(frame: NSRect(x: 0, y: 40, width: 300, height: 32))
        other.controller = fixture.controller
        other.configure(id: UUID(), text: "Another entry", rtl: false)
        fixture.parent.contentView?.addSubview(other)
        fixture.controller.request(from: fixture.anchor)
        let stale = fixture.clock.entries.last!
        fixture.clock.advance(0.25)
        fixture.controller.request(from: other)
        fixture.anchor.cancelPreview(); stale.action()
        fixture.clock.advance(0.25)
        XCTAssertFalse(fixture.controller.panel?.isVisible ?? false)
        fixture.clock.advance(0.25)
        XCTAssertEqual(fixture.displayedText, "Another entry")
    }

    func testExitReplacementAndDismantleRejectLateCallbacks() {
        let fixture = Fixture(); defer { fixture.finish() }
        fixture.controller.request(from: fixture.anchor)
        let first = fixture.clock.entries.last!
        fixture.anchor.cancelPreview(); first.action()
        XCTAssertNil(fixture.controller.panel)
        fixture.controller.request(from: fixture.anchor)
        let replaced = fixture.clock.entries.last!
        fixture.anchor.configure(id: UUID(), text: "Replacement", rtl: false)
        replaced.action()
        XCTAssertNil(fixture.controller.panel)
        fixture.controller.request(from: fixture.anchor)
        let removed = fixture.clock.entries.last!
        fixture.anchor.removeFromSuperview(); removed.action()
        XCTAssertNil(fixture.controller.panel)
    }

    func testHiddenParentAndClosedPopoverCannotShowOrRetainPreview() {
        let fixture = Fixture(); defer { fixture.finish() }
        fixture.controller.request(from: fixture.anchor)
        fixture.parent.orderOut(nil); fixture.clock.advance(0.5)
        XCTAssertFalse(fixture.controller.panel?.isVisible ?? false)
        fixture.parent.orderFront(nil)
        fixture.controller.request(from: fixture.anchor)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: nil)
        fixture.clock.advance(0.5)
        XCTAssertFalse(fixture.controller.panel?.isVisible ?? false)
        fixture.controller.request(from: fixture.anchor); fixture.clock.advance(0.5)
        XCTAssertTrue(fixture.controller.panel?.isVisible == true)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: nil)
        XCTAssertFalse(fixture.controller.panel?.isVisible ?? false)
        XCTAssertNil(fixture.controller.panel?.contentView)
    }

    func testPointerMustStillBeInsideAtTheDeadline() {
        let fixture = Fixture(); defer { fixture.finish() }
        let clock = Clock()
        let controller = ClipboardHoverController(schedule: { clock.schedule($0, $1) }, containsPointer: { _ in false })
        defer { controller.cancel() }
        controller.request(from: fixture.anchor); clock.advance(0.5)
        XCTAssertNil(controller.panel)
    }

    func testTrackingIsClickThroughAndFrameChangeCancelsPendingPreview() {
        let fixture = Fixture(); defer { fixture.finish() }
        fixture.anchor.updateTrackingAreas()
        XCTAssertNil(fixture.anchor.hitTest(.zero))
        XCTAssertEqual(fixture.anchor.trackingAreas.count, 1)
        XCTAssertTrue(fixture.anchor.trackingAreas[0].options.contains(.activeAlways))
        fixture.controller.request(from: fixture.anchor)
        fixture.anchor.setFrameOrigin(NSPoint(x: 0, y: 40)); fixture.clock.advance(0.5)
        XCTAssertNil(fixture.controller.panel)
    }

    func testLocalClickKeyAndScrollEventsDismissThePreview() throws {
        let fixture = Fixture(); defer { fixture.finish() }
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
            modifierFlags: [], timestamp: 0, windowNumber: fixture.parent.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: fixture.parent.windowNumber, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53))
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                         wheel1: 1, wheel2: 0, wheel3: 0))
        let scroll = try XCTUnwrap(NSEvent(cgEvent: wheel))
        for event in [mouse, key, scroll] {
            fixture.controller.request(from: fixture.anchor); fixture.clock.advance(0.5)
            XCTAssertTrue(fixture.controller.panel?.isVisible == true)
            NSApp.sendEvent(event)
            XCTAssertFalse(fixture.controller.panel?.isVisible ?? false, "\(event.type)")
        }
    }

    func testProgrammaticScrollInvalidatesThePendingPreview() {
        let fixture = Fixture(); defer { fixture.finish() }
        let scroll = NSScrollView(frame: fixture.parent.contentView!.bounds)
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 600))
        fixture.anchor.removeFromSuperview(); document.addSubview(fixture.anchor)
        scroll.documentView = document; fixture.parent.contentView = scroll
        fixture.controller.request(from: fixture.anchor)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        fixture.clock.advance(0.5)
        XCTAssertNil(fixture.controller.panel)
    }

    func testRenderedPreviewFitsScreenAndSupportsBothThemesAndRTL() throws {
        let theme = UserDefaults.standard.object(forKey: Theme.themeKey)
        defer {
            if let theme { UserDefaults.standard.set(theme, forKey: Theme.themeKey) }
            else { UserDefaults.standard.removeObject(forKey: Theme.themeKey) }
        }
        for dark in [false, true] {
            UserDefaults.standard.set(dark ? "dark" : "light", forKey: Theme.themeKey)
            let fixture = Fixture(text: String(repeating: "Detailed paragraph with a long message. ", count: 40))
            defer { fixture.finish() }
            fixture.anchor.configure(id: UUID(), text: fixture.anchor.previewText, rtl: true)
            fixture.controller.request(from: fixture.anchor); fixture.clock.advance(0.5)
            let panel = try XCTUnwrap(fixture.controller.panel)
            XCTAssertTrue(fixture.screen.contains(panel.frame))
            XCTAssertLessThanOrEqual(panel.frame.height, 360)
            let content = try XCTUnwrap(panel.contentView)
            let label = try XCTUnwrap(content.subviews.first as? NSTextField)
            let style = label.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            XCTAssertEqual(style?.baseWritingDirection, .rightToLeft)
            if let directory = ProcessInfo.processInfo.environment["HOP_HOVER_RENDER_DIR"] {
                let url = URL(fileURLWithPath: directory); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("hover-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
