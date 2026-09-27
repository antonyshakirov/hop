import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class SteadyFieldTests: XCTestCase {
    private final class Draft: ObservableObject {
        @Published var text = ""
        @Published var focused = false
    }

    private struct Editor: View {
        @ObservedObject var draft: Draft

        var body: some View {
            SteadyField(text: $draft.text, focus: $draft.focused)
        }
    }

    func testTypingKeepsProjectNameFieldFocused() {
        let draft = Draft()
        let host = NSHostingView(rootView: Editor(draft: draft))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
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

    private func pump() {
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
