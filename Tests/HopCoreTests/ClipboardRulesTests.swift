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

    // MARK: - classify (capture order)

    func testClassifyPrefersFilesOverImagePreview() {
        // a copied icon file carries both a file URL and a thumbnail preview —
        // the file must win so it never lands as a "1024 × 1024" image row
        let out = ClipboardRules.classify(fileURLPaths: ["/a/icon.png"], hasImage: true, text: "icon.png")
        XCTAssertEqual(out, .files(["/a/icon.png"]))
    }

    func testClassifyImageWhenNoFileURL() {
        XCTAssertEqual(ClipboardRules.classify(fileURLPaths: [], hasImage: true, text: nil), .image)
    }

    func testClassifyTextWhenNoFileOrImage() {
        XCTAssertEqual(ClipboardRules.classify(fileURLPaths: [], hasImage: false, text: "hello"), .text("hello"))
    }

    func testClassifyFilesBeatTextEvenWithoutImage() {
        let out = ClipboardRules.classify(fileURLPaths: ["/a/b.zip"], hasImage: false, text: "b.zip")
        XCTAssertEqual(out, .files(["/a/b.zip"]))
    }

    func testClassifyIgnoresEmptyPasteboard() {
        XCTAssertEqual(ClipboardRules.classify(fileURLPaths: [], hasImage: false, text: nil), .ignore)
        XCTAssertEqual(ClipboardRules.classify(fileURLPaths: [], hasImage: false, text: "  \n "), .ignore)
        // stray empty path strings don't make a file entry
        XCTAssertEqual(ClipboardRules.classify(fileURLPaths: [""], hasImage: false, text: nil), .ignore)
    }

    func testClassifyKeepsMultipleFilePaths() {
        let out = ClipboardRules.classify(fileURLPaths: ["/a/1", "/a/2"], hasImage: false, text: nil)
        XCTAssertEqual(out, .files(["/a/1", "/a/2"]))
    }

    // MARK: - file label

    func testFileLabelSingleIsTheName() {
        XCTAssertEqual(ClipboardRules.fileLabel(for: ["/a/b/notes.txt"]), "notes.txt")
    }

    func testFileLabelMultipleAppendsCount() {
        XCTAssertEqual(ClipboardRules.fileLabel(for: ["/a/one.txt", "/a/two.txt", "/a/three.txt"]),
                       "one.txt +2")
    }

    // MARK: - remembering files

    func testRememberingFileInsertsFileEntryWithName() {
        let out = ClipboardRules.remembering(files: ["/a/report.pdf"], in: [])
        XCTAssertEqual(out?.first?.text, "report.pdf")
        XCTAssertEqual(out?.first?.filePaths, ["/a/report.pdf"])
        XCTAssertNil(out?.first?.imageFile)
    }

    func testRememberingEmptyFileListIsIgnored() {
        XCTAssertNil(ClipboardRules.remembering(files: [], in: []))
    }

    func testRememberingSameFileSetOnTopChangesNothing() {
        let items = [ClipboardItem(text: "report.pdf", filePaths: ["/a/report.pdf"])]
        XCTAssertNil(ClipboardRules.remembering(files: ["/a/report.pdf"], in: items))
    }

    func testRememberingFileSetDeeperMovesToTop() {
        let items = [
            ClipboardItem(text: "a.txt", filePaths: ["/a/a.txt"]),
            item("some text"),
            ClipboardItem(text: "b.txt", filePaths: ["/a/b.txt"]),
        ]
        let out = ClipboardRules.remembering(files: ["/a/b.txt"], in: items)
        XCTAssertEqual(out?.map(\.text), ["b.txt", "a.txt", "some text"])
        XCTAssertEqual(out?.first?.filePaths, ["/a/b.txt"])
    }

    func testFileEntryNeverTakesPartInTextDedup() {
        // a file entry labeled "notes.txt" must not be swallowed by copying the
        // literal text "notes.txt"
        let items = [ClipboardItem(text: "notes.txt", filePaths: ["/a/notes.txt"])]
        let out = ClipboardRules.remembering("notes.txt", in: items)
        XCTAssertEqual(out?.count, 2)
        XCTAssertNil(out?.first?.filePaths)                 // fresh plain-text entry on top
        XCTAssertEqual(out?.last?.filePaths, ["/a/notes.txt"]) // file entry preserved
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
