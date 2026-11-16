import XCTest
@testable import HopCore

final class ClipboardHoverPreviewTests: XCTestCase {
    func testPreviewPreservesParagraphsAndTextBeyondTheOneLineLabel() {
        let body = "  first line\n\n" + String(repeating: "detailed text ", count: 40)
        XCTAssertEqual(ClipboardHoverPreview.text(for: .init(text: body)), body)
        XCTAssertGreaterThan(ClipboardHoverPreview.text(for: .init(text: body)).count,
                             ClipboardRules.previewLine(body).count)
    }

    func testLargeBodyIsBoundedAndExplicitlyTruncatedWithoutSplittingCharacters() {
        let character = "👨‍👩‍👧‍👦"
        let body = String(repeating: character, count: 2000)
        let preview = ClipboardHoverPreview.text(for: .init(text: body))
        XCTAssertEqual(preview, String(repeating: character, count: 1500) + "…")
        XCTAssertEqual(ClipboardHoverPreview.text(for: .init(text: String(repeating: "a", count: 1500))).count, 1500)
    }

    func testNewlineFloodFitsTheLineLimitAndSignalsTheOmittedTail() {
        let preview = ClipboardHoverPreview.text(for: .init(text: String(repeating: "line\n", count: 1000)))
        XCTAssertEqual(preview.components(separatedBy: "\n").count, 20)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testExternalBodyUsesItsAvailableHeadAndSignalsMoreContent() {
        let item = ClipboardItem(text: "stored body head", textFile: "missing.txt", textBytes: 30000)
        XCTAssertEqual(ClipboardHoverPreview.text(for: item), "stored body head…")
    }

    func testFilesShowTheirPathsRatherThanTheCollapsedCountLabel() {
        let item = ClipboardItem(text: "notes.txt +1", filePaths: ["/sample/notes.txt", "/sample/second.txt"])
        XCTAssertEqual(ClipboardHoverPreview.text(for: item), "/sample/notes.txt\n/sample/second.txt")
        let many = ClipboardItem(text: "notes +9", filePaths: (0..<10).map { "/sample/\($0).txt" })
        XCTAssertEqual(ClipboardHoverPreview.text(for: many).components(separatedBy: "\n").count, 8)
        XCTAssertTrue(ClipboardHoverPreview.text(for: many).hasSuffix("7.txt…"))
    }

    func testImagesAndColorsKeepTheirActualContentLabels() {
        XCTAssertEqual(ClipboardHoverPreview.text(for: .init(text: "882 × 120", imageFile: "preview.png")), "882 × 120")
        XCTAssertEqual(ClipboardHoverPreview.text(for: .init(text: "#336699", colorHex: "336699")), "#336699")
    }
}
