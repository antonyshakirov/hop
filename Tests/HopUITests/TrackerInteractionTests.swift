import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class TrackerInteractionTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []

    func testProjectNameKeepsEditorBetweenLettersAndCommits() throws {
        try checkAdding(project: true)
    }

    func testTaskNameKeepsEditorBetweenLettersAndCommits() throws {
        try checkAdding(project: false)
    }

    private func checkAdding(project: Bool) throws {
        _ = NSApplication.shared
        let tracker = TrackerController(demo: true)
        let host = NSHostingView(rootView: TrackerView(tracker: tracker, lang: .en)
            .frame(width: 340, alignment: .topLeading))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 340, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        Self.retainedFixtures.append(contentsOf: [tracker as AnyObject, host, window])
        defer { window.orderOut(nil) }
        pump()
        host.layoutSubtreeIfNeeded()
        let point = host.convert(NSPoint(x: project ? host.bounds.maxX - 45 : 45,
                                         y: host.bounds.maxY - 13), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
            pump()
        }
        let field = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(window.makeFirstResponder(field))
        for name in ["Launch project", "Second item"] {
            var typed = ""
            for letter in name {
                let editor = try XCTUnwrap(field.currentEditor(), "Editor disappeared after \(typed)")
                editor.insertText(String(letter))
                typed.append(letter)
                tracker.objectWillChange.send()
                pump()
                XCTAssertNotNil(field.currentEditor(), "Caret was lost after \(typed)")
                XCTAssertEqual(field.stringValue, typed)
            }
            try key("\r", code: 36, window: window)
            XCTAssertNotNil(field.currentEditor(), "Return must retain the add field")
            XCTAssertEqual(field.stringValue, "")
        }
        let names = project ? tracker.engine.data.projects.map(\.name)
            : tracker.engine.data.tasks.map(\.name)
        XCTAssertEqual(names, ["Launch project", "Second item"])
        field.currentEditor()?.insertText("Discard")
        pump()
        try key("\u{1b}", code: 53, window: window)
        XCTAssertNil(field.currentEditor())
        XCTAssertTrue(descendants(host).compactMap { $0 as? NSTextField }.isEmpty)
        XCTAssertEqual(project ? tracker.engine.data.projects.count : tracker.engine.data.tasks.count, 2)
    }

    private func key(_ characters: String, code: UInt16, window: NSWindow) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        window.sendEvent(event)
        pump()
    }

    private func pump() {
        for _ in 0..<8 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
