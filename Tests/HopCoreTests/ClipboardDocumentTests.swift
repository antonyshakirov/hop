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

    // MARK: - Formats

    func testEveryFormatNamesItsOwnExtension() {
        XCTAssertEqual(ClipboardDocument.Format.allCases.map(\.fileExtension),
                       ["txt", "md", "pdf", "docx"])
    }

    func testOnlyTextFormatsAreWrittenAsIs() {
        XCTAssertTrue(ClipboardDocument.Format.txt.isPlainText)
        XCTAssertTrue(ClipboardDocument.Format.md.isPlainText)
        XCTAssertFalse(ClipboardDocument.Format.pdf.isPlainText)
        XCTAssertFalse(ClipboardDocument.Format.docx.isPlainText)
    }

    func testAnUnknownStoredFormatFallsBackToText() {
        XCTAssertEqual(ClipboardDocument.Format.named("rtf"), .txt)
        XCTAssertEqual(ClipboardDocument.Format.named("pdf"), .pdf)
    }

    func testTheDuplicateRuleFollowsTheFormat() {
        let existing: Set<String> = ["note.pdf"]
        XCTAssertEqual(ClipboardDocument.uniqueName("note", ext: "pdf",
                                                    taken: { existing.contains($0) }),
                       "note 2.pdf")
    }
}
