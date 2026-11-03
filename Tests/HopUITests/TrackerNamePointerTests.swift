import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class TrackerNamePointerTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []

    func testWindowMovementDoesNotChangePointerScreenDelta() throws {
        _ = NSApplication.shared
        let surface = TrackerNamePointer.Surface(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        surface.origin = CGPoint(x: 10, y: 20)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 100, height: 20),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        window.orderFrontRegardless()
        Self.retainedFixtures.append(contentsOf: [surface, window])
        defer { window.orderOut(nil) }
        let start = surface.convert(NSPoint(x: 10, y: 10), to: nil)
        let moved = NSPoint(x: start.x + 10, y: start.y - 5)
        let originalFrameOrigin = window.frame.origin
        surface.onChanged = { _ in
            window.setFrameOrigin(NSPoint(x: originalFrameOrigin.x + 30, y: originalFrameOrigin.y + 40))
        }
        var finished: TrackerNamePointer.Value?
        surface.onEnded = { finished = $0 }
        NSApp.postEvent(try mouse(.leftMouseDragged, point: moved, window: window), atStart: false)
        NSApp.postEvent(try mouse(.leftMouseUp, point: NSPoint(x: moved.x - 30, y: moved.y - 40),
                                 window: window), atStart: false)
        surface.mouseDown(with: try mouse(.leftMouseDown, point: start, window: window))
        let value = try XCTUnwrap(finished)
        XCTAssertEqual(value.translation.width, 10, accuracy: 0.001)
        XCTAssertEqual(value.translation.height, 5, accuracy: 0.001)
        XCTAssertEqual(value.location.x, 30, accuracy: 0.001)
        XCTAssertEqual(value.location.y, 35, accuracy: 0.001)
    }

    func testPointerMovesTaskIntoOpenProjectAndPreservesHistory() throws {
        try checkMove(expanded: true)
    }

    func testPointerMovesTaskIntoFoldedProjectAndPreservesHistory() throws {
        try checkMove(expanded: false)
    }

    func testEscapeCancelsPointerMoveAndReleasesCapture() throws {
        let tracker = TrackerController(demo: true)
        let task = tracker.engine.addTask(name: "Draft")
        _ = tracker.engine.addProject(name: "Launch")
        var capture: [Bool] = []
        let (host, window) = show(tracker, capture: { capture.append($0) })
        defer { window.orderOut(nil) }
        let surface = try pointer(task, in: host)
        let start = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: nil)
        let original = tracker.engine.data
        NSApp.postEvent(try mouse(.leftMouseDragged, point: NSPoint(x: start.x + 12, y: start.y - 10),
                                 window: window), atStart: false)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        NSApp.postEvent(escape, atStart: false)
        surface.mouseDown(with: try mouse(.leftMouseDown, point: start, window: window))
        pump()
        XCTAssertEqual(tracker.engine.data.tasks, original.tasks)
        XCTAssertEqual(tracker.engine.data.rootOrder, original.rootOrder)
        XCTAssertEqual(capture, [true, false])
        let restored = try pointer(task, in: host)
        let restoredPoint = restored.convert(NSPoint(x: restored.bounds.midX, y: restored.bounds.midY), to: nil)
        XCTAssertEqual(restoredPoint.x, start.x, accuracy: 0.5)
        XCTAssertEqual(restoredPoint.y, start.y, accuracy: 0.5)
    }

    func testProjectNameClickOpensOneRenameFieldWithoutMoving() throws {
        let tracker = TrackerController(demo: true)
        let project = tracker.engine.addProject(name: "Launch")
        let (host, window) = show(tracker)
        defer { window.orderOut(nil) }
        let surface = try pointer(project, in: host)
        let point = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: nil)
        NSApp.postEvent(try mouse(.leftMouseUp, point: point, window: window), atStart: false)
        surface.mouseDown(with: try mouse(.leftMouseDown, point: point, window: window))
        pump()
        let fields = descendants(host).compactMap { $0 as? NSTextField }
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields.first?.stringValue, "Launch")
        XCTAssertNotNil(fields.first?.currentEditor())
        XCTAssertEqual(tracker.engine.data.projects.map(\.id), [project])
    }

    func testTaskDoubleClickKeepsItsCardOpen() throws {
        let tracker = TrackerController(demo: true)
        let task = tracker.engine.addTask(name: "Draft")
        let (host, window) = show(tracker)
        defer { window.orderOut(nil) }
        for count in [1, 2] {
            let surface = try pointer(task, in: host)
            let point = surface.convert(NSPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: nil)
            NSApp.postEvent(try mouse(.leftMouseUp, point: point, window: window), atStart: false)
            surface.mouseDown(with: try mouse(.leftMouseDown, point: point, window: window, clickCount: count))
            pump()
        }
        XCTAssertFalse(descendants(host).compactMap { $0 as? NSTextView }.isEmpty)
        XCTAssertEqual(tracker.engine.data.tasks.map(\.id), [task])
    }

    private func checkMove(expanded: Bool) throws {
        let tracker = TrackerController(demo: true)
        let task = tracker.engine.addTask(name: "Draft")
        let project = tracker.engine.addProject(name: "Launch")
        tracker.engine.setProjectExpanded(project, expanded)
        tracker.engine.start(taskID: task)
        tracker.engine.stop(taskID: task)
        tracker.engine.set(taskID: task, period: .total, to: 120)
        let intervals = tracker.engine.data.intervals
        let corrections = tracker.engine.data.corrections
        var capture: [Bool] = []
        let (host, window) = show(tracker, capture: { capture.append($0) })
        defer { window.orderOut(nil) }
        let source = try pointer(task, in: host)
        let target = try pointer(project, in: host)
        let start = source.convert(NSPoint(x: source.bounds.midX, y: source.bounds.midY), to: nil)
        let end = target.convert(NSPoint(x: target.bounds.midX, y: target.bounds.midY), to: nil)
        for (type, point) in [(NSEvent.EventType.leftMouseDragged, NSPoint(x: start.x + 12, y: start.y - 1)),
                              (.leftMouseDragged, end), (.leftMouseUp, end)] {
            NSApp.postEvent(try mouse(type, point: point, window: window), atStart: false)
        }
        source.mouseDown(with: try mouse(.leftMouseDown, point: start, window: window))
        pump()
        XCTAssertEqual(tracker.engine.data.tasks.first { $0.id == task }?.projectID, project)
        XCTAssertEqual(tracker.engine.tasks(in: project).map(\.id), [task])
        XCTAssertFalse(tracker.engine.data.rootOrder.contains(task))
        XCTAssertEqual(tracker.engine.data.intervals, intervals)
        XCTAssertEqual(tracker.engine.data.corrections, corrections)
        XCTAssertEqual(tracker.engine.amount(taskID: task, period: .total), 120, accuracy: 0.001)
        XCTAssertEqual(capture, [true, false])
    }

    private func show(_ tracker: TrackerController, capture: @escaping (Bool) -> Void = { _ in })
        -> (NSHostingView<AnyView>, NSWindow) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AnyView(TrackerView(tracker: tracker, lang: .en,
            onDraggingChanged: capture).frame(width: 340)))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 340, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        Self.retainedFixtures.append(contentsOf: [tracker as AnyObject, host, window])
        pump()
        host.layoutSubtreeIfNeeded()
        return (host, window)
    }

    private func pointer(_ id: UUID, in host: NSView) throws -> TrackerNamePointer.Surface {
        try XCTUnwrap(descendants(host).compactMap { $0 as? TrackerNamePointer.Surface }.first {
            $0.identifier?.rawValue == "tracker-name-" + id.uuidString
        })
    }

    private func mouse(_ type: NSEvent.EventType, point: NSPoint, window: NSWindow, clickCount: Int = 1) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1))
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func pump() {
        for _ in 0..<8 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
}
