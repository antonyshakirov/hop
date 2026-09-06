import XCTest
@testable import HopCore

final class HTMLConversionTests: XCTestCase {
    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/\(name)") }
    private func web(_ text: String) -> URL { URL(string: text)! }

    // MARK: - What counts as a page

    func testTheSavedPageFormatsAreRecognised() {
        for name in ["index.html", "notes.htm", "article.webarchive", "page.mhtml", "page.mht"] {
            XCTAssertTrue(HTMLConversion.isPage(file(name)), name)
        }
    }

    func testTheExtensionIsReadWithoutRegardToCase() {
        XCTAssertTrue(HTMLConversion.isPage(file("INDEX.HTML")))
    }

    func testDocumentsAndMediaAreNotPages() {
        for name in ["report.docx", "scan.pdf", "notes.md", "clip.mp4", "shot.png"] {
            XCTAssertFalse(HTMLConversion.isPage(file(name)), name)
        }
    }

    // MARK: - What a page can become

    func testMarkdownIsWrittenWithTheShortExtensionAndTheRestUseTheirOwnName() {
        XCTAssertEqual(HTMLConversion.Target.markdown.fileExtension, "md")
        XCTAssertEqual(HTMLConversion.Target.pdf.fileExtension, "pdf")
        XCTAssertEqual(HTMLConversion.Target.docx.fileExtension, "docx")
        XCTAssertEqual(HTMLConversion.Target.rtf.fileExtension, "rtf")
        XCTAssertEqual(HTMLConversion.Target.txt.fileExtension, "txt")
        XCTAssertEqual(HTMLConversion.Target.png.fileExtension, "png")
    }

    func testTheChipReadsAsTheExtensionItProduces() {
        for target in HTMLConversion.Target.allCases {
            XCTAssertEqual(target.label, target.fileExtension, target.rawValue)
        }
    }

    func testOnlyPdfAndTheSnapshotRenderThePage() {
        XCTAssertTrue(HTMLConversion.Target.pdf.rendersPage)
        XCTAssertTrue(HTMLConversion.Target.png.rendersPage)
        for target in [HTMLConversion.Target.docx, .markdown, .rtf, .txt] {
            XCTAssertFalse(target.rendersPage, target.rawValue)
        }
    }

    // MARK: - A pasted address

    func testAnAddressWithItsSchemeIsTakenAsIs() {
        XCTAssertEqual(HTMLConversion.address(fromPasted: "https://example.com/a"),
                       web("https://example.com/a"))
        XCTAssertEqual(HTMLConversion.address(fromPasted: "http://example.com"),
                       web("http://example.com"))
    }

    func testSurroundingWhitespaceAndLineBreaksAreTrimmed() {
        XCTAssertEqual(HTMLConversion.address(fromPasted: "  https://example.com/a \n"),
                       web("https://example.com/a"))
    }

    func testAHostWithoutASchemeIsReadOverHttps() {
        XCTAssertEqual(HTMLConversion.address(fromPasted: "example.com/article"),
                       web("https://example.com/article"))
        XCTAssertEqual(HTMLConversion.address(fromPasted: "www.example.com"),
                       web("https://www.example.com"))
    }

    func testOrdinaryTextIsNotAnAddress() {
        for text in ["just some text", "read example.com later", "notes", "", "   "] {
            XCTAssertNil(HTMLConversion.address(fromPasted: text), text)
        }
    }

    func testOnlyTheWebSchemesAreAccepted() {
        for text in ["ftp://example.com", "file:///tmp/page.html", "javascript:alert(1)"] {
            XCTAssertNil(HTMLConversion.address(fromPasted: text), text)
        }
    }

    func testAPathIsAFileNotAnAddress() {
        XCTAssertNil(HTMLConversion.address(fromPasted: "/Users/anton/page.html"))
        XCTAssertNil(HTMLConversion.address(fromPasted: "~/Downloads/page.html"))
    }

    func testABareFilenameIsNotAnAddress() {
        for text in ["page.html", "report.docx", "clip.mp4", "archive.zip"] {
            XCTAssertNil(HTMLConversion.address(fromPasted: text), text)
        }
    }

    func testASiteWithAPageOfThatNameIsStillAnAddress() {
        XCTAssertEqual(HTMLConversion.address(fromPasted: "example.com/page.html"),
                       web("https://example.com/page.html"))
    }

    // MARK: - Telling batch rows apart

    func testTwoSitesWithTheSamePathAreDifferentRows() {
        XCTAssertNotEqual(HTMLConversion.batchKey(web("https://example.com/post")),
                          HTMLConversion.batchKey(web("https://other.com/post")))
    }

    func testTheSameAddressIsTheSameRow() {
        XCTAssertEqual(HTMLConversion.batchKey(web("https://example.com/post")),
                       HTMLConversion.batchKey(web("https://example.com/post")))
    }

    func testAFileIsStillToldApartByItsPath() {
        XCTAssertEqual(HTMLConversion.batchKey(file("a.html")),
                       HTMLConversion.batchKey(file("a.html")))
        XCTAssertNotEqual(HTMLConversion.batchKey(file("a.html")),
                          HTMLConversion.batchKey(file("b.html")))
    }

    // MARK: - Where the result lands

    func testAnAddressHasNoFolderOfItsOwn() {
        XCTAssertFalse(HTMLConversion.hasOwnFolder(web("https://example.com/post")))
        XCTAssertTrue(HTMLConversion.hasOwnFolder(file("page.html")))
    }

    // MARK: - What the result is called

    func testAFileKeepsItsOwnName() {
        XCTAssertEqual(HTMLConversion.outputName(for: file("report.html"), title: "Anything"),
                       "report")
    }

    func testAnAddressIsNamedAfterThePage() {
        XCTAssertEqual(
            HTMLConversion.outputName(for: web("https://example.com/a"), title: "How Hop Works"),
            "How Hop Works")
    }

    func testATitleThatWouldBreakAFilenameIsCleaned() {
        XCTAssertEqual(
            HTMLConversion.outputName(for: web("https://example.com/a"), title: "A/B: testing"),
            "A-B testing")
    }

    func testAVeryLongTitleIsCutToSomethingAFilesystemAccepts() {
        let long = String(repeating: "a", count: 300)
        let name = HTMLConversion.outputName(for: web("https://example.com/a"), title: long)
        XCTAssertLessThanOrEqual(name.count, 80)
        XCTAssertFalse(name.isEmpty)
    }

    func testWithoutATitleThePageIsNamedAfterItsAddress() {
        XCTAssertEqual(HTMLConversion.outputName(for: web("https://example.com/blog/post"),
                                                 title: nil),
                       "post")
        XCTAssertEqual(HTMLConversion.outputName(for: web("https://example.com/"), title: nil),
                       "example.com")
        XCTAssertEqual(HTMLConversion.outputName(for: web("https://example.com"), title: nil),
                       "example.com")
    }

    func testABlankTitleIsNoTitle() {
        XCTAssertEqual(HTMLConversion.outputName(for: web("https://example.com/blog/post"),
                                                 title: "   "),
                       "post")
    }

    // MARK: - The snapshot of a whole page

    func testAPageShorterThanTheCapIsSnappedAtFullSize() {
        XCTAssertEqual(HTMLConversion.snapshotScale(contentHeight: 4000, cap: 16000), 1)
        XCTAssertEqual(HTMLConversion.snapshotScale(contentHeight: 16000, cap: 16000), 1)
    }

    func testATallerPageShrinksToFitTheCap() {
        XCTAssertEqual(HTMLConversion.snapshotScale(contentHeight: 32000, cap: 16000), 0.5,
                       accuracy: 0.0001)
    }

    func testAPageWithNoMeasuredHeightIsLeftAlone() {
        XCTAssertEqual(HTMLConversion.snapshotScale(contentHeight: 0, cap: 16000), 1)
        XCTAssertEqual(HTMLConversion.snapshotScale(contentHeight: -10, cap: 16000), 1)
    }
}
