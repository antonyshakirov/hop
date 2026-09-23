import XCTest
@testable import HopCore

final class ProductLinkTests: XCTestCase {
    func testEnglishIsTheBareDomain() {
        XCTAssertEqual(ProductLink.page(for: "en"), "https://hop.tools/")
    }

    /// Every language the app speaks has a page of its own on the site, the
    /// fifteen the old footer sent to English included.
    func testEveryOtherLanguageHasItsOwnPage() {
        for code in ["ru", "de", "es", "pt", "fr", "it", "zh", "ja", "nl", "ko", "th",
                     "vi", "hi", "id", "tr", "pl", "sr", "ar", "he", "fa", "ur"] {
            XCTAssertEqual(ProductLink.page(for: code), "https://hop.tools/\(code)/", code)
        }
    }

    /// A code the site does not publish falls back to the English page rather
    /// than to a link that answers 404.
    func testAnUnknownCodeFallsBackToEnglish() {
        XCTAssertEqual(ProductLink.page(for: "xx"), "https://hop.tools/")
        XCTAssertEqual(ProductLink.page(for: ""), "https://hop.tools/")
    }

    func testTheRepositoryLink() {
        XCTAssertEqual(ProductLink.repository, "https://github.com/antonyshakirov/hop")
    }
}
