import XCTest
@testable import HopCore

final class ClipboardRulesTests: XCTestCase {
    private func item(_ text: String, image: String? = nil) -> ClipboardItem {
        ClipboardItem(text: text, imageFile: image)
    }

    // MARK: - remembering

    func testEmptyAndWhitespaceTextIsIgnored() {
        XCTAssertNil(ClipboardRules.remembering("", in: []))
        XCTAssertNil(ClipboardRules.remembering("  \n\t ", in: []))
    }

    func testFirstCopyGoesToTop() {
        let out = ClipboardRules.remembering("hello", in: [])
        XCTAssertEqual(out?.map(\.text), ["hello"])
    }

    func testTextIsTrimmedAndTruncated() {
        let out = ClipboardRules.remembering("  hello \n", in: [])
        XCTAssertEqual(out?.first?.text, "hello")

        let book = String(repeating: "a", count: ClipboardRules.maxItemLength + 500)
        let truncated = ClipboardRules.remembering(book, in: [])
        XCTAssertEqual(truncated?.first?.text.count, ClipboardRules.maxItemLength)
    }

    func testExactRepeatOfTopEntryChangesNothing() {
        let items = [item("hello"), item("world")]
        XCTAssertNil(ClipboardRules.remembering("hello", in: items))
    }

    func testCapitalizationChangeUpdatesTopEntryInPlace() {
        let items = [item("hello")]
        let out = ClipboardRules.remembering("Hello", in: items)
        XCTAssertEqual(out?.map(\.text), ["Hello"])
        XCTAssertEqual(out?.first?.id, items[0].id) // same entry, not a new one
    }

    func testGrowingDictationReplacesTopEntry() {
        let items = [item("hello wor"), item("older")]
        let out = ClipboardRules.remembering("hello world", in: items)
        XCTAssertEqual(out?.map(\.text), ["hello world", "older"])
        XCTAssertEqual(out?.first?.id, items[0].id)
    }

    func testShrinkingRetakeReplacesTopEntry() {
        let items = [item("hello world")]
        let out = ClipboardRules.remembering("hello", in: items)
        XCTAssertEqual(out?.map(\.text), ["hello"])
        XCTAssertEqual(out?.first?.id, items[0].id)
    }

    func testDuplicateDeeperInHistoryMovesToTopAsNewEntry() {
        let items = [item("aaa"), item("bbb"), item("ccc")]
        let out = ClipboardRules.remembering("bbb", in: items)
        XCTAssertEqual(out?.map(\.text), ["bbb", "aaa", "ccc"])
    }

    func testImageEntryNeverTakesPartInTextDedup() {
        // an image labeled "1280 × 800" must not swallow the same copied text
        let items = [item("1280 × 800", image: "shot.png")]
        let out = ClipboardRules.remembering("1280 × 800", in: items)
        XCTAssertEqual(out?.count, 2)
        XCTAssertNil(out?.first?.imageFile)
        XCTAssertEqual(out?.last?.imageFile, "shot.png")
    }

    // MARK: - pruned

    func testPrunedTrimsTailBeyondMaxItems() {
        let items = (0..<5).map { item("\($0)") }
        let (kept, removed) = ClipboardRules.pruned(items, maxItems: 3, maxImageItems: 20)
        XCTAssertEqual(kept.map(\.text), ["0", "1", "2"])
        XCTAssertEqual(removed.map(\.text), ["3", "4"])
    }

    func testPrunedEnforcesImageCapKeepingText() {
        let items = [
            item("i1", image: "1.png"), item("t1"),
            item("i2", image: "2.png"), item("t2"),
            item("i3", image: "3.png"),
        ]
        let (kept, removed) = ClipboardRules.pruned(items, maxItems: 100, maxImageItems: 2)
        XCTAssertEqual(kept.map(\.text), ["i1", "t1", "i2", "t2"])
        XCTAssertEqual(removed.map(\.text), ["i3"]) // oldest image falls off
    }

    func testPrunedRemovedListDrivesFileCleanup() {
        // whatever is removed must reference its file so the caller can delete it
        let items = (0..<3).map { item("i\($0)", image: "\($0).png") }
        let (_, removed) = ClipboardRules.pruned(items, maxItems: 100, maxImageItems: 1)
        XCTAssertEqual(removed.compactMap(\.imageFile), ["1.png", "2.png"])
    }

    func testWithinCapsNothingChanges() {
        let items = [item("a"), item("b", image: "b.png")]
        let (kept, removed) = ClipboardRules.pruned(items, maxItems: 10, maxImageItems: 10)
        XCTAssertEqual(kept, items)
        XCTAssertTrue(removed.isEmpty)
    }
}
