import XCTest
@testable import HopCore

final class DownloadMirrorsTests: XCTestCase {
    private let manifest = URL(string: "https://hop.tools/downloads/hop/latest.json?v=2.0.0")!

    func testTheURLSOwnHostIsTriedFirst() {
        let urls = DownloadMirrors.alternatives(for: manifest)
        XCTAssertEqual(urls.first?.host, "hop.tools")
        XCTAssertEqual(urls.map(\.host), ["hop.tools", "ru.hop.tools"])
    }

    func testAMirrorURLKeepsItsOwnHostFirst() {
        let url = URL(string: "https://ru.hop.tools/downloads/hop/Hop.zip")!
        XCTAssertEqual(DownloadMirrors.alternatives(for: url).map(\.host),
                       ["ru.hop.tools", "hop.tools"])
    }

    func testOnlyTheHostChanges() {
        let mirrored = DownloadMirrors.alternatives(for: manifest).last
        XCTAssertEqual(mirrored?.absoluteString,
                       "https://ru.hop.tools/downloads/hop/latest.json?v=2.0.0")
    }

    func testAForeignHostIsLeftAlone() {
        let url = URL(string: "https://github.com/antonyshakirov/hop/releases/latest")!
        XCTAssertEqual(DownloadMirrors.alternatives(for: url), [url])
    }

    func testAManifestCanAddAHost() {
        XCTAssertEqual(DownloadMirrors.hosts(declared: ["dl.hop.tools"]),
                       ["hop.tools", "ru.hop.tools", "dl.hop.tools"])
    }

    func testAHostAlreadyShippedIsNotAddedTwice() {
        XCTAssertEqual(DownloadMirrors.hosts(declared: ["ru.hop.tools", "RU.HOP.TOOLS"]),
                       ["hop.tools", "ru.hop.tools"])
    }

    func testAnythingThatIsNotAPlainHostIsIgnored() {
        XCTAssertEqual(
            DownloadMirrors.hosts(declared: [
                "https://evil.example/x", "hop.tools:8443", "localhost", "", " ",
                "../hop.tools", "1.2.3.4/downloads",
            ]),
            ["hop.tools", "ru.hop.tools"]
        )
    }
}
