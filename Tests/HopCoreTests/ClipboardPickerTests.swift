import XCTest
@testable import HopCore

final class ClipboardPickerTests: XCTestCase {
    private let command: UInt = 1 << 20

    func testSearchRetainsHistoryIdentityAndOrderForEveryContentType() {
        let items = [ClipboardItem(text: "NOTES", filePaths: ["/synthetic/notes"]),
                     ClipboardItem(text: "book notes", textFile: "book.txt", textBytes: 50000),
                     ClipboardItem(text: "picture", imageFile: "image.png")]
        XCTAssertEqual(ClipboardPicker.results(in: items, query: "  nOtEs\n"), Array(items.prefix(2)))
        XCTAssertEqual(ClipboardPicker.results(in: items, query: " \n"), items)
        XCTAssertTrue(ClipboardPicker.results(in: items, query: "absent").isEmpty)
    }

    func testNumberKeysUsePhysicalPositionsAndOnlyCommand() {
        for (index, code) in [18, 19, 20, 21, 23, 22, 26, 28, 25].enumerated() {
            XCTAssertEqual(ClipboardPicker.action(keyCode: UInt16(code), modifiers: command), .choose(index))
            XCTAssertEqual(ClipboardPicker.action(keyCode: UInt16(code), modifiers: command | (1 << 16)), .choose(index))
            for other in [UInt(0), 1 << 17, 1 << 18, 1 << 19] {
                if other == 0 {
                    XCTAssertNil(ClipboardPicker.action(keyCode: UInt16(code), modifiers: 0))
                } else {
                    XCTAssertNil(ClipboardPicker.action(keyCode: UInt16(code), modifiers: command | other))
                }
            }
        }
        XCTAssertNil(ClipboardPicker.action(keyCode: 29, modifiers: command))
        XCTAssertNil(ClipboardPicker.action(keyCode: 8, modifiers: command))
    }

    func testSelectionSurvivesNewEntriesAndClampsAtEitherEnd() {
        let items = [ClipboardItem(text: "one"), ClipboardItem(text: "two"), ClipboardItem(text: "three")]
        XCTAssertEqual(ClipboardPicker.moving(id: nil, by: 1, in: items), items[1].id)
        XCTAssertEqual(ClipboardPicker.moving(id: items[0].id, by: -1, in: items), items[0].id)
        XCTAssertEqual(ClipboardPicker.moving(id: items[2].id, by: 1, in: items), items[2].id)
        XCTAssertEqual(ClipboardPicker.selectedIndex(id: items[1].id,
            in: [ClipboardItem(text: "new")] + items), 2)
        XCTAssertEqual(ClipboardPicker.selectedIndex(id: UUID(), in: items), 0)
        XCTAssertNil(ClipboardPicker.moving(id: nil, by: 1, in: []))
        XCTAssertNil(ClipboardPicker.selectedIndex(id: nil, in: []))
    }

    func testNavigationDoesNotClaimModifiedEditorKeys() {
        XCTAssertEqual(ClipboardPicker.action(keyCode: 125, modifiers: 0), .move(1))
        XCTAssertEqual(ClipboardPicker.action(keyCode: 126, modifiers: 0), .move(-1))
        XCTAssertEqual(ClipboardPicker.action(keyCode: 36, modifiers: 0), .copySelection)
        XCTAssertEqual(ClipboardPicker.action(keyCode: 53, modifiers: 0), .dismiss)
        XCTAssertNil(ClipboardPicker.action(keyCode: 125, modifiers: command))
        XCTAssertNil(ClipboardPicker.action(keyCode: 36, modifiers: 1 << 19))
    }
}
