import AppKit
import HopCore
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class NumericFieldTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        super.tearDown()
    }

    private final class Values: ObservableObject {
        @Published var stored = 100
        @Published var visible = 3
        @Published var rate = 1234
        @Published var slider = 20
        @Published var unit: RateUnit = .kb
    }

    private struct Fields: View {
        @ObservedObject var values: Values

        var body: some View {
            VStack {
                NumericField(value: $values.stored, range: 5...300)
                NumericField(value: $values.visible, range: 1...10)
                RateLimitField(kb: $values.rate, unit: values.unit)
                MiniSlider(value: $values.slider, range: 10...100)
            }
        }
    }

    func testTenVisibleRowsSurviveMovingToTheStorageField() throws {
        let (values, window, fields) = try fixture()
        let visible = try XCTUnwrap(fields.first { $0.stringValue == "3" })
        let storage = try XCTUnwrap(fields.first { $0.stringValue == "100" })
        window.makeFirstResponder(visible)
        let editor = try XCTUnwrap(visible.currentEditor())
        editor.selectAll(nil)
        editor.insertText("10")
        pump()
        window.makeFirstResponder(storage)
        pump()
        XCTAssertEqual(values.visible, 10)
        XCTAssertEqual(visible.stringValue, "10")
        XCTAssertEqual(values.stored, 100)
    }

    func testImmediateFocusTransferStillCommitsTheTypedNumber() throws {
        let (values, window, fields) = try fixture()
        let storage = try XCTUnwrap(fields.first { $0.stringValue == "100" })
        let visible = try XCTUnwrap(fields.first { $0.stringValue == "3" })
        window.makeFirstResponder(storage)
        let editor = try XCTUnwrap(storage.currentEditor())
        editor.selectAll(nil)
        editor.insertText("2")
        window.makeFirstResponder(visible)
        pump()
        XCTAssertEqual(values.stored, 5)
        XCTAssertEqual(storage.stringValue, "5")
        XCTAssertNotNil(visible.currentEditor(), "An old field reclaimed the caret")
    }

    func testRapidReturnDoesNotLetAnOldBlurClearTheCaret() throws {
        let (_, window, fields) = try fixture()
        let storage = try XCTUnwrap(fields.first { $0.stringValue == "100" })
        let visible = try XCTUnwrap(fields.first { $0.stringValue == "3" })
        window.makeFirstResponder(visible)
        visible.currentEditor()?.insertText("9")
        pump()
        window.makeFirstResponder(storage)
        storage.currentEditor()?.insertText("8")
        window.makeFirstResponder(visible)
        pump()
        XCTAssertNotNil(visible.currentEditor())
    }

    func testRateLimitSurvivesImmediateFocusTransfer() throws {
        let (values, window, fields) = try fixture()
        let rate = try XCTUnwrap(fields.first { $0.stringValue == "1234" })
        let visible = try XCTUnwrap(fields.first { $0.stringValue == "3" })
        window.makeFirstResponder(rate)
        rate.currentEditor()?.selectAll(nil)
        rate.currentEditor()?.insertText("500")
        window.makeFirstResponder(visible)
        pump()
        XCTAssertEqual(values.rate, 500)
        XCTAssertEqual(rate.stringValue, "500")
        XCTAssertNotNil(visible.currentEditor())
    }

    func testSliderNumberClampsBeforeMovingToAnotherField() throws {
        let (values, window, fields) = try fixture()
        let slider = try XCTUnwrap(fields.first { $0.stringValue == "20" })
        let visible = try XCTUnwrap(fields.first { $0.stringValue == "3" })
        window.makeFirstResponder(slider)
        slider.currentEditor()?.selectAll(nil)
        slider.currentEditor()?.insertText("1")
        window.makeFirstResponder(visible)
        pump()
        XCTAssertEqual(values.slider, 10)
        XCTAssertEqual(slider.stringValue, "10")
        XCTAssertNotNil(visible.currentEditor())
    }

    func testUnitChangesOnlyReformatTheStoredRate() throws {
        let (values, window, fields) = try fixture()
        let rate = try XCTUnwrap(fields.first { $0.stringValue == "1234" })
        let visible = try XCTUnwrap(fields.first { $0.stringValue == "3" })
        window.makeFirstResponder(rate)
        values.unit = .mb
        pump()
        window.makeFirstResponder(visible)
        pump()
        XCTAssertEqual(values.rate, 1234)
        XCTAssertEqual(rate.stringValue, "1.2")
    }

    func testFocusingAnUntouchedLegacyValueDoesNotRewriteIt() throws {
        let (values, window, fields) = try fixture()
        let storage = try XCTUnwrap(fields.first { $0.stringValue == "100" })
        let visible = try XCTUnwrap(fields.first { $0.stringValue == "3" })
        values.stored = 0
        pump()
        window.makeFirstResponder(storage)
        window.makeFirstResponder(visible)
        pump()
        XCTAssertEqual(values.stored, 0)
    }

    private func fixture() throws -> (Values, NSWindow, [NSTextField]) {
        _ = NSApplication.shared
        let values = Values()
        let host = NSHostingView(rootView: Fields(values: values))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        Self.retainedFixtures.append(contentsOf: [values as AnyObject, host, window])
        windows.append(window)
        pump()
        host.layoutSubtreeIfNeeded()
        return (values, window, descendants(of: host).compactMap { $0 as? NSTextField })
    }

    private func pump() {
        for _ in 0..<4 { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
