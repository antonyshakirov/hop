import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class SteadyFieldTests: XCTestCase {
    // WORKAROUND: XCTest crashes while releasing this AppKit fixture on macOS 27.
    private static var retainedFixtures: [AnyObject] = []

    func testDurationPlaceholderAndValueKeepTheirRenderedRightEdgeInBothThemes() throws {
        for dark in [false, true] {
            let draft = Draft()
            let host = NSHostingView(rootView: Editor(draft: draft, duration: true)
                .frame(width: 74, height: 18)
                .background(dark ? Color.black : Color.white))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 74, height: 18),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.orderFrontRegardless()
            Self.retainedFixtures.append(contentsOf: [draft as AnyObject, host, window])
            defer { window.orderOut(nil) }
            pump()

            func renderedRightEdge(_ name: String) throws -> Int {
                host.layoutSubtreeIfNeeded()
                let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: image)
                if let directory = ProcessInfo.processInfo.environment["HOP_ISSUE_PROBE_ARTIFACT_DIR"] {
                    try XCTUnwrap(image.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
                }
                var right: Int?
                for y in 0..<image.pixelsHigh {
                    for x in 0..<image.pixelsWide {
                        guard let colour = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                        let background: CGFloat = dark ? 0.0 : 1.0
                        let difference = abs(colour.redComponent - background)
                            + abs(colour.greenComponent - background) + abs(colour.blueComponent - background)
                        if difference > 0.3 { right = max(right ?? x, x) }
                    }
                }
                return try XCTUnwrap(right, "The field must render visible glyphs")
            }
            let theme = dark ? "dark" : "light"
            let placeholder = try renderedRightEdge("placeholder-\(theme)")
            draft.text = "0:00:00"
            pump()
            let value = try renderedRightEdge("value-\(theme)")
            XCTAssertLessThanOrEqual(abs(placeholder - value), 1, "Placeholder and value must share the right edge")
        }
    }

    private final class Draft: ObservableObject {
        @Published var text = ""
        @Published var focused = false
        @Published var committed = ""
    }

    private struct Editor: View {
        @ObservedObject var draft: Draft
        var exitsOnPointerLeave = false
        var duration = false

        var body: some View {
            SteadyField(text: $draft.text, placeholder: duration ? "0:00:00" : "",
                        alignment: duration ? .right : .natural, focus: $draft.focused,
                        onEndEditing: { draft.committed = draft.text },
                        onOutsideInteraction: exitsOnPointerLeave ? { draft.focused = false } : nil)
        }
    }

    func testOpeningFieldAllowsActivationAndHandlesKeyEvents() throws {
        _ = NSApplication.shared
        let draft = Draft()
        let host = NSHostingView(rootView: Editor(draft: draft))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        _ = StatusItemController.preventActivation(of: window)
        window.orderFrontRegardless()
        Self.retainedFixtures.append(contentsOf: [draft as AnyObject, host, window])
        defer { window.orderOut(nil) }
        pump()

        draft.focused = true
        pump()
        let field = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSTextField }.first)
        XCTAssertNotNil(field.currentEditor())
        let getter = Selector(("_preventsActivation"))
        if #available(macOS 27.0, *) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            XCTAssertTrue(window.responds(to: getter))
            XCTAssertFalse(unsafeBitCast(window.method(for: getter), to: Getter.self)(window, getter),
                           "Opening a field must release the nonactivating window tag")
        }
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        for letter in "Draft" {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: String(letter), charactersIgnoringModifiers: String(letter),
                isARepeat: false, keyCode: 0))
            editor.keyDown(with: event)
            pump()
        }
        XCTAssertEqual(draft.text, "Draft")
    }

    func testTypingKeepsProjectNameFieldFocused() {
        let draft = Draft()
        let host = NSHostingView(rootView: Editor(draft: draft))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        Self.retainedFixtures.append(contentsOf: [draft as AnyObject, host, window])
        host.layoutSubtreeIfNeeded()

        draft.focused = true
        pump()
        guard let field = descendants(of: host).compactMap({ $0 as? NSTextField }).first else {
            return XCTFail("SteadyField did not create a text field")
        }
        XCTAssertNotNil(field.currentEditor())

        for letter in "Project" {
            field.currentEditor()?.insertText(String(letter))
            pump()
            XCTAssertNotNil(field.currentEditor(), "Focus fell after typing \(letter)")
        }
        XCTAssertEqual(draft.text, "Project")

        draft.focused = false
        host.layoutSubtreeIfNeeded()
        draft.focused = true
        host.layoutSubtreeIfNeeded()
        pump()
        XCTAssertNotNil(field.currentEditor(), "An obsolete focus request removed the caret")
    }

    func testPointerExitFieldSharesFocusAndFinishesItsLastEdit() throws {
        _ = NSApplication.shared
        let draft = Draft()
        let host = NSHostingView(rootView: Editor(draft: draft, exitsOnPointerLeave: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        Self.retainedFixtures.append(contentsOf: [draft as AnyObject, host, window])
        pump()
        let field = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSTextField }.first)
        window.makeFirstResponder(field)
        XCTAssertTrue(draft.focused)
        field.currentEditor()?.insertText("75")
        let event = try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0,
            trackingNumber: 0, userData: nil))
        field.mouseExited(with: event)
        pump()
        XCTAssertFalse(draft.focused)
        XCTAssertNil(field.currentEditor())
        XCTAssertEqual(draft.committed, "75")
    }

    private func pump() {
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
