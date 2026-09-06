import XCTest
@testable import HopCore

final class HTMLSourceTests: XCTestCase {
    // MARK: - What is taken out

    func testAScriptGoesAndTakesItsContentWithIt() {
        let html = "<p>before</p><script>var x = 1 < 2;</script><p>after</p>"
        XCTAssertEqual(HTMLSource.readable(html), "<p>before</p><p>after</p>")
    }

    func testAStyleBlockGoesTheSameWay() {
        let html = "<p>a</p><style>body { color: red }</style><p>b</p>"
        XCTAssertEqual(HTMLSource.readable(html), "<p>a</p><p>b</p>")
    }

    func testTheTagsThatFetchSomethingAreRemoved() {
        for tag in ["<img src=\"http://e.com/a.png\">",
                    "<link rel=\"stylesheet\" href=\"http://e.com/a.css\">",
                    "<source srcset=\"http://e.com/a.webp\">",
                    "<embed src=\"http://e.com/a.swf\">"] {
            XCTAssertEqual(HTMLSource.readable("<p>a</p>\(tag)<p>b</p>"),
                           "<p>a</p><p>b</p>", tag)
        }
    }

    func testAnIframeGoesWithWhateverIsInsideIt() {
        let html = "<p>a</p><iframe src=\"http://e.com\"><p>fallback</p></iframe><p>b</p>"
        XCTAssertEqual(HTMLSource.readable(html), "<p>a</p><p>b</p>")
    }

    func testTagNamesAreMatchedWithoutRegardToCase() {
        XCTAssertEqual(HTMLSource.readable("<p>a</p><SCRIPT>x</SCRIPT><IMG SRC='b.png'><p>b</p>"),
                       "<p>a</p><p>b</p>")
    }

    // MARK: - What stays

    func testStructureAndEmphasisAreLeftAlone() {
        let html = "<h1>Title</h1><p>text with <b>bold</b> and <em>italic</em></p>"
        XCTAssertEqual(HTMLSource.readable(html), html)
    }

    func testALinkKeepsItsAddress() {
        let html = "<p>see <a href=\"https://example.com\">this</a></p>"
        XCTAssertEqual(HTMLSource.readable(html), html)
    }

    func testALessThanSignInTextSurvives() {
        let html = "<p>2 < 3 and 4 > 1</p>"
        XCTAssertEqual(HTMLSource.readable(html), html)
    }

    func testAnEmptyDocumentComesBackEmpty() {
        XCTAssertEqual(HTMLSource.readable(""), "")
    }

    // MARK: - Malformed input

    func testAnUnclosedScriptDoesNotEatWhatCameBeforeIt() {
        XCTAssertEqual(HTMLSource.readable("<p>a</p><script>var x = 1"), "<p>a</p>")
    }

    func testAnUnterminatedTagAtTheEndIsDropped() {
        XCTAssertEqual(HTMLSource.readable("<p>a</p><img src=\"x"), "<p>a</p>")
    }
}
