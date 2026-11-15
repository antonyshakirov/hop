import AppKit
import XCTest
import HopCore
@testable import Hop

@MainActor
final class ClipboardPickerWindowTests: XCTestCase {
    func testMarkedTextKeepsNavigationAndConfirmationInTheEditor() {
        let clipboard = ClipboardController(demo: true)
        var copied: [ClipboardItem] = []
        let picker = ClipboardPickerWindow(clipboard: clipboard, copy: { copied.append($0) })
        picker.model.update([ClipboardItem(text: "test")])
        let editor = NSTextView(frame: .zero)
        editor.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        for code: UInt16 in [36, 53, 125, 126] {
            XCTAssertFalse(picker.handle(keyCode: code, modifiers: 0, editor: editor))
        }
        XCTAssertTrue(copied.isEmpty)
    }

    func testAChangedEntryIsReadAtTheMomentItIsChosen() {
        let clipboard = ClipboardController(demo: true)
        var copied: [ClipboardItem] = []
        let picker = ClipboardPickerWindow(clipboard: clipboard, copy: { copied.append($0) })
        let old = ClipboardItem(text: "draft")
        var updated = old
        updated.text = "draft extended"
        picker.model.update([updated])
        picker.choose(old)
        XCTAssertEqual(copied, [updated])
    }

    func testFilteredNumberSelectionUsesTheExistingCompleteEntry() {
        let clipboard = ClipboardController(demo: true)
        var copied: [ClipboardItem] = []
        let picker = ClipboardPickerWindow(clipboard: clipboard, copy: { copied.append($0) })
        let wanted = ClipboardItem(text: "notes preview", textFile: "whole.txt",
                                   textBytes: 50000, textDigest: "synthetic-digest")
        let picture = ClipboardItem(text: "notes picture", imageFile: "synthetic.png")
        let files = ClipboardItem(text: "notes files", filePaths: ["/synthetic/file"])
        let items = [ClipboardItem(text: "other"), wanted, picture, files]
        picker.model.update(items)
        picker.model.query = "notes"
        XCTAssertTrue(picker.handle(keyCode: 18, modifiers: NSEvent.ModifierFlags.command.rawValue))
        XCTAssertEqual(copied, [wanted])
        XCTAssertEqual(picker.model.items, items)
        XCTAssertTrue(picker.handle(keyCode: 19, modifiers: NSEvent.ModifierFlags.command.rawValue))
        XCTAssertTrue(picker.handle(keyCode: 20, modifiers: NSEvent.ModifierFlags.command.rawValue))
        XCTAssertEqual(copied, [wanted, picture, files])
    }

    func testSearchResetsSelectionAndArrowsFollowFilteredResults() {
        let clipboard = ClipboardController(demo: true)
        var copied: [ClipboardItem] = []
        let picker = ClipboardPickerWindow(clipboard: clipboard, copy: { copied.append($0) })
        let items = [ClipboardItem(text: "one"), ClipboardItem(text: "two"), ClipboardItem(text: "three")]
        picker.model.update(items)
        XCTAssertTrue(picker.handle(keyCode: 125, modifiers: 0))
        XCTAssertEqual(picker.model.selection, items[1])
        picker.model.query = "th"
        XCTAssertEqual(picker.model.selection, items[2])
        XCTAssertTrue(picker.handle(keyCode: 36, modifiers: 0))
        XCTAssertEqual(copied, [items[2]])
    }

    func testEmptyMissingDigitsAndEscapeNeverCopy() {
        let clipboard = ClipboardController(demo: true)
        var copied: [ClipboardItem] = []
        let picker = ClipboardPickerWindow(clipboard: clipboard, copy: { copied.append($0) })
        picker.model.update([ClipboardItem(text: "one")])
        XCTAssertTrue(picker.handle(keyCode: 25, modifiers: NSEvent.ModifierFlags.command.rawValue))
        XCTAssertTrue(picker.handle(keyCode: 53, modifiers: 0))
        picker.model.query = "absent"
        XCTAssertTrue(picker.handle(keyCode: 18, modifiers: NSEvent.ModifierFlags.command.rawValue))
        XCTAssertTrue(picker.handle(keyCode: 36, modifiers: 0))
        XCTAssertFalse(picker.handle(keyCode: 8, modifiers: NSEvent.ModifierFlags.command.rawValue))
        XCTAssertTrue(copied.isEmpty)
    }
}
