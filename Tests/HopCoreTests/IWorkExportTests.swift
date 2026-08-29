import XCTest
@testable import HopCore

final class IWorkExportTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }

    // MARK: - Which application owns the document

    func testEachExtensionFindsItsApplication() {
        XCTAssertEqual(IWorkExport.app(for: url("report.pages")), .pages)
        XCTAssertEqual(IWorkExport.app(for: url("budget.numbers")), .numbers)
        XCTAssertEqual(IWorkExport.app(for: url("deck.key")), .keynote)
    }

    func testTheExtensionIsReadWithoutRegardToCase() {
        XCTAssertEqual(IWorkExport.app(for: url("REPORT.PAGES")), .pages)
    }

    func testAnythingElseBelongsToNobody() {
        for name in ["notes.docx", "sheet.xlsx", "clip.mp4", "plain.txt"] {
            XCTAssertNil(IWorkExport.app(for: url(name)), name)
            XCTAssertFalse(IWorkExport.isExportable(url(name)), name)
        }
    }

    // MARK: - What each one can be asked for

    func testEveryApplicationOffersPdfAndItsOwnOfficeFormat() {
        XCTAssertEqual(IWorkExport.targets(for: .pages), [.pdf, .docx])
        XCTAssertEqual(IWorkExport.targets(for: .numbers), [.pdf, .xlsx])
        XCTAssertEqual(IWorkExport.targets(for: .keynote), [.pdf, .pptx])
    }

    func testATargetThatDoesNotApplyFallsBackToPdf() {
        // asking Numbers for a .docx is not a failure, it is a PDF
        XCTAssertEqual(IWorkExport.resolvedTarget(.docx, for: .numbers), .pdf)
        XCTAssertEqual(IWorkExport.resolvedTarget(.xlsx, for: .numbers), .xlsx)
        XCTAssertEqual(IWorkExport.resolvedTarget(.pptx, for: .pages), .pdf)
    }

    // MARK: - The script

    func testTheScriptTalksToTheRightApplicationAndFormat() {
        let script = IWorkExport.script(input: url("budget.numbers"),
                                        output: url("budget.xlsx"), target: .xlsx)!
        XCTAssertTrue(script.contains("tell application \"Numbers\""))
        XCTAssertTrue(script.contains("as Microsoft Excel"))
        XCTAssertTrue(script.contains("/tmp/budget.numbers"))
        XCTAssertTrue(script.contains("/tmp/budget.xlsx"))
    }

    func testTheDocumentIsClosedWithoutSaving() {
        // a batch must never modify what it was handed
        let script = IWorkExport.script(input: url("a.pages"), output: url("a.pdf"),
                                        target: .pdf)!
        XCTAssertTrue(script.contains("close hopDoc saving no"))
    }

    func testAPathWithQuotesCannotBreakOutOfTheScript() {
        let script = IWorkExport.script(input: url("we\"ird.pages"),
                                        output: url("out.pdf"), target: .pdf)!
        XCTAssertTrue(script.contains("we\\\"ird.pages"))
        // the tell block is still exactly one statement per line
        XCTAssertEqual(script.components(separatedBy: "tell application").count - 1, 1)
    }

    func testABackslashIsEscapedBeforeTheQuotes() {
        XCTAssertEqual(IWorkExport.escaped("a\\b\"c"), "a\\\\b\\\"c")
    }

    func testAFileNobodyOwnsHasNoScript() {
        XCTAssertNil(IWorkExport.script(input: url("clip.mp4"), output: url("clip.pdf"),
                                        target: .pdf))
    }

    // MARK: - Reading a failure

    func testPermissionRefusalIsRecognised() {
        XCTAssertTrue(IWorkExport.isPermissionRefusal(
            "Not authorized to send Apple events to Pages. (-1743)"))
        XCTAssertFalse(IWorkExport.isPermissionRefusal("The document could not be opened."))
    }

    func testAMissingApplicationIsRecognised() {
        XCTAssertTrue(IWorkExport.isMissingApp("Application isn’t running. (-600)"))
        XCTAssertFalse(IWorkExport.isMissingApp("Not authorized to send Apple events (-1743)"))
    }
}
