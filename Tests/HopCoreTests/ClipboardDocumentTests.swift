import XCTest
@testable import HopCore

/// Naming a file after the text that goes into it.
final class ClipboardDocumentTests: XCTestCase {

    func testTheNameIsTheTextItself() {
        XCTAssertEqual(ClipboardDocument.fileName(for: "shopping list"), "shopping list")
    }

    func testOnlyTheFirstLine() {
        XCTAssertEqual(ClipboardDocument.fileName(for: "title\nbody of the note"), "title")
    }

    func testLongTextIsCutToOneLine() {
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(ClipboardDocument.fileName(for: long).count, ClipboardDocument.nameLimit)
    }

    func testCharactersAFileNameCannotHoldAreDropped() {
        XCTAssertEqual(ClipboardDocument.fileName(for: "in/out: report?"), "inout report")
    }

    func testWhitespaceIsCollapsed() {
        XCTAssertEqual(ClipboardDocument.fileName(for: "  two   words  "), "two words")
    }

    func testALeadingDotWouldHideTheFile() {
        XCTAssertEqual(ClipboardDocument.fileName(for: ".hidden thing"), "hidden thing")
    }

    func testTextThatSurvivesNothingFallsBack() {
        XCTAssertEqual(ClipboardDocument.fileName(for: "///"), "clipboard")
        XCTAssertEqual(ClipboardDocument.fileName(for: "   "), "clipboard")
    }

    // MARK: - Not overwriting the previous save

    func testAFreeNameIsUsedAsIs() {
        XCTAssertEqual(ClipboardDocument.uniqueName("note", taken: { _ in false }), "note.txt")
    }

    func testATakenNameGetsTheNextNumber() {
        let existing: Set<String> = ["note.txt", "note 2.txt"]
        XCTAssertEqual(ClipboardDocument.uniqueName("note", taken: { existing.contains($0) }),
                       "note 3.txt")
    }

    func testTheExtensionIsAddedOnce() {
        XCTAssertTrue(ClipboardDocument.uniqueName("a", taken: { _ in false }).hasSuffix(".txt"))
    }
}
