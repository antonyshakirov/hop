import XCTest
@testable import HopCore

final class UpdateFeedTests: XCTestCase {
    private let feed = "https://www.antonshakirov.com/downloads/hop/latest.json"

    func testCarriesTheRunningVersion() {
        let url = UpdateFeed.checkURL(feed: feed, version: "1.4.0")
        XCTAssertEqual(url?.absoluteString, feed + "?v=1.4.0")
    }

    /// The path has to survive untouched — the manifest is a static file and a
    /// mangled path is a silent 404, i.e. an app that stops updating.
    func testKeepsThePathIntact() {
        let url = UpdateFeed.checkURL(feed: feed, version: "1.4.0")
        XCTAssertEqual(url?.path, "/downloads/hop/latest.json")
    }

    /// A bundle-less run (swift run, snapshots) can hand over an empty string.
    /// Better a plain request than "?v=" polluting the log.
    func testSkipsTheParameterWhenTheVersionIsBlank() {
        XCTAssertEqual(UpdateFeed.checkURL(feed: feed, version: "")?.absoluteString, feed)
        XCTAssertEqual(UpdateFeed.checkURL(feed: feed, version: "   ")?.absoluteString, feed)
    }

    func testEscapesAVersionThatIsNotURLSafe() {
        let url = UpdateFeed.checkURL(feed: feed, version: "1.5.0 beta+1")
        XCTAssertEqual(url?.query, "v=1.5.0%20beta+1")
        XCTAssertEqual(
            URLComponents(url: url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value,
            "1.5.0 beta+1"
        )
    }

    /// Anything short of an absolute address is refused outright: a relative
    /// leftover would be requested, fail, and look like the site being down.
    func testReturnsNilForAFeedThatIsNotAnAbsoluteURL() {
        XCTAssertNil(UpdateFeed.checkURL(feed: "", version: "1.4.0"))
        XCTAssertNil(UpdateFeed.checkURL(feed: "downloads/hop/latest.json", version: "1.4.0"))
        XCTAssertNil(UpdateFeed.checkURL(feed: "/downloads/hop/latest.json", version: "1.4.0"))
    }
}
