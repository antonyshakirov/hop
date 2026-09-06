import XCTest
@testable import HopCore

final class ClipboardPreviewTests: XCTestCase {
    func testNewlinesBecomeOneLine() {
        XCTAssertEqual(ClipboardRules.previewLine("first\nsecond"), "first second")
        XCTAssertEqual(ClipboardRules.previewLine("first\r\n\r\nsecond"), "first second")
        XCTAssertEqual(ClipboardRules.previewLine("first\tsecond"), "first second")
    }

    func testTheEdgesAreTrimmed() {
        XCTAssertEqual(ClipboardRules.previewLine("\n\n  hello  \n"), "hello")
        XCTAssertEqual(ClipboardRules.previewLine(""), "")
        XCTAssertEqual(ClipboardRules.previewLine("\n\n\n"), "")
    }

    /// The point of the whole function: a copied book is not folded in full on
    /// every redraw.
    func testALongEntryStopsAtTheRowWidth() {
        let book = String(repeating: "a", count: ClipboardRules.maxItemLength)
        XCTAssertEqual(ClipboardRules.previewLine(book).count, ClipboardRules.previewLength)
    }

    func testTheFirstLineSurvivesWhateverFollowsIt() {
        let text = "the line that is shown\n" + String(repeating: "tail\n", count: 5_000)
        XCTAssertTrue(ClipboardRules.previewLine(text).hasPrefix("the line that is shown"))
    }

    func testTextThatIsAlreadyOneLineComesBackUnchanged() {
        XCTAssertEqual(ClipboardRules.previewLine("https://hop.tools"), "https://hop.tools")
    }
}
