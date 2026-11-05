import AppKit
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class TrackerHistoryInteractionTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []

    func testDurationEditKeepsExactStartAndSurvivesReloadInBothThemes() throws {
        for dark in [false, true] {
            let f = try show(dark: dark)
            defer { f.close() }
            try f.openHistory()
            let field = try f.durationField()
            XCTAssertEqual(field.stringValue, "0:10:00")
            XCTAssertNotNil(field.currentEditor(), "Opening history must request keyboard focus")
            try f.type("0:15:00", into: field)
            try f.key("\r", code: 36)
            XCTAssertEqual(f.tracker.engine.total(taskID: f.task), 900)
            XCTAssertEqual(f.tracker.engine.history(taskID: f.task).first?.moment, f.start)
            let restored = TrackerController(storeDir: f.directory)
            XCTAssertEqual(restored.engine.total(taskID: f.task), 900)
            XCTAssertEqual(restored.engine.history(taskID: f.task).first?.moment, f.start)
            try f.openHistory()
            XCTAssertEqual(try f.durationField().stringValue, "0:15:00")
            try f.snapshot("duration-\(dark ? "dark" : "light")")
        }
    }

    func testDurationLabelOpensTheExistingSession() throws {
        let f = try show()
        defer { f.close() }
        try f.openHistory(x: 340)
        XCTAssertEqual(try f.durationField().stringValue, "0:10:00")
    }

    func testChangingStartKeepsDurationAndSurvivesReload() throws {
        let f = try show()
        defer { f.close() }
        try f.openHistory()
        let field = try f.durationField()
        let center = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: f.host)
        try f.click(NSPoint(x: 110, y: center.y))
        f.fit()
        try f.snapshot("hour-list")
        try f.click(NSPoint(x: 45, y: center.y + 100))
        f.fit()
        try f.snapshot("start-draft")
        let commitField = try f.durationField()
        let commitCenter = commitField.convert(NSPoint(x: commitField.bounds.midX, y: commitField.bounds.midY), to: f.host)
        try f.click(NSPoint(x: f.host.bounds.maxX - 24, y: commitCenter.y))
        let expected = Calendar.current.date(bySettingHour: 10, minute: 17, second: 0, of: f.start)
        XCTAssertEqual(f.tracker.engine.total(taskID: f.task), 600)
        XCTAssertEqual(f.tracker.engine.history(taskID: f.task).first?.moment, expected)
        let restored = TrackerController(storeDir: f.directory)
        XCTAssertEqual(restored.engine.total(taskID: f.task), 600)
        XCTAssertEqual(restored.engine.history(taskID: f.task).first?.moment, expected)
        XCTAssertEqual(restored.engine.data.intervals.map(\.id), f.tracker.engine.data.intervals.map(\.id))
    }

    func testEscapeDiscardsDurationDraft() throws {
        let f = try show()
        defer { f.close() }
        let original = f.tracker.engine.data.intervals
        try f.openHistory()
        try f.type("0:45:00", into: f.durationField())
        try f.key("\u{1b}", code: 53)
        XCTAssertEqual(f.tracker.engine.data.intervals, original)
        XCTAssertEqual(TrackerController(storeDir: f.directory).engine.data.intervals, original)
    }

    func testRunningSessionRemainsReadOnly() throws {
        let f = try show(running: true)
        defer { f.close() }
        let original = f.tracker.engine.data.intervals
        for x in [90.0, 340.0] {
            try f.openHistory(x: x)
            XCTAssertTrue(f.fields.isEmpty)
            XCTAssertEqual(f.tracker.engine.data.intervals, original)
        }
    }

    private func show(dark: Bool = true, running: Bool = false) throws -> Fixture {
        _ = NSApplication.shared
        let f = try Fixture(dark: dark, running: running)
        Self.retainedFixtures.append(f)
        return f
    }

    @MainActor
    private final class Fixture {
        let savedTheme: Any?
        let directory: URL
        let tracker: TrackerController
        let task: UUID
        let start: Date
        let host: FirstMouseHostingView<AnyView>
        let window: NSWindow

        init(dark: Bool, running: Bool) throws {
            savedTheme = UserDefaults.standard.object(forKey: Theme.themeKey)
            directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            tracker = TrackerController(storeDir: directory)
            task = tracker.engine.addTask(name: "Recorded session")
            start = Calendar.current.date(bySettingHour: 9, minute: 17, second: 37, of: Date())!.addingTimeInterval(0.375)
            if running { tracker.engine.start(taskID: task) }
            else { tracker.engine.addSession(taskID: task, seconds: 600, startingAt: start) }
            UserDefaults.standard.set(dark ? "dark" : "light", forKey: Theme.themeKey)
            host = FirstMouseHostingView(rootView: AnyView(TrackerView(tracker: tracker, lang: .en)
                .frame(width: 368).background(Theme.background)
                .environment(\.colorScheme, dark ? .dark : .light)))
            window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 368, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            pump()
            let pointer = try XCTUnwrap(descendants(host).compactMap { $0 as? TrackerNamePointer.Surface }.first {
                $0.identifier?.rawValue == "tracker-name-" + task.uuidString
            })
            let point = pointer.convert(NSPoint(x: pointer.bounds.midX, y: pointer.bounds.midY), to: nil)
            NSApp.postEvent(try event(.leftMouseUp, point), atStart: false)
            pointer.mouseDown(with: try event(.leftMouseDown, point))
            pump()
            fit()
        }

        var fields: [NSTextField] { descendants(host).compactMap { $0 as? NSTextField } }

        func durationField() throws -> NSTextField {
            try XCTUnwrap(fields.first { $0.placeholderAttributedString?.string == "0:00:00" })
        }

        func openHistory(x: CGFloat = 90) throws {
            fit()
            try click(NSPoint(x: x, y: host.bounds.maxY - 70))
            fit()
        }

        func click(_ local: NSPoint) throws {
            let point = host.convert(local, to: nil)
            let down = try event(.leftMouseDown, point)
            NSApp.postEvent(try event(.leftMouseUp, point), atStart: false)
            NSApp.sendEvent(down)
            if let up = window.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .eventTracking, dequeue: true) {
                NSApp.sendEvent(up)
            }
            pump()
        }

        func type(_ text: String, into field: NSTextField) throws {
            XCTAssertTrue(window.makeFirstResponder(field))
            field.selectText(nil)
            for character in text {
                try XCTUnwrap(field.currentEditor()).insertText(String(character))
                tracker.objectWillChange.send()
                pump()
                XCTAssertNotNil(field.currentEditor())
            }
        }

        func key(_ text: String, code: UInt16) throws {
            NSApp.sendEvent(try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)))
            pump()
            fit()
        }

        func fit() {
            host.frame.size = host.fittingSize
            window.setContentSize(host.frame.size)
            host.layoutSubtreeIfNeeded()
            pump()
        }

        func close() {
            window.orderOut(nil)
            if let savedTheme { UserDefaults.standard.set(savedTheme, forKey: Theme.themeKey) }
            else { UserDefaults.standard.removeObject(forKey: Theme.themeKey) }
            if tracker.isTracking { tracker.engine.stop(taskID: task) }
            try? FileManager.default.removeItem(at: directory)
        }

        func snapshot(_ name: String) throws {
            guard let dir = ProcessInfo.processInfo.environment["HOP_ISSUE_PROBE_ARTIFACT_DIR"] else { return }
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            try XCTUnwrap(image.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }

        private func event(_ type: NSEvent.EventType, _ point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
        }

        private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        private func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
    }
}
