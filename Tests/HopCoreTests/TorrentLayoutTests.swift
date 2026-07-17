import XCTest
@testable import HopCore

final class TorrentLayoutTests: XCTestCase {
    func testSingleFileWritesDirectly() {
        // One file IS the payload — no wrapper folder.
        XCTAssertNil(TorrentLayout.subfolder(torrentName: "Ubuntu.iso", fileCount: 1))
    }

    func testMultiFileNestsUnderTorrentName() {
        XCTAssertEqual(
            TorrentLayout.subfolder(torrentName: "Game of Thrones S08 400p Amedia", fileCount: 24),
            "Game of Thrones S08 400p Amedia"
        )
    }

    func testNameSanitizedToOneComponent() {
        // Path separators would break out of the chosen folder — collapse them.
        XCTAssertEqual(
            TorrentLayout.subfolder(torrentName: "season/1: extras", fileCount: 3),
            "season-1- extras"
        )
    }

    func testUnusableNameFallsBackToNoWrapper() {
        XCTAssertNil(TorrentLayout.subfolder(torrentName: "   ", fileCount: 5))
        XCTAssertNil(TorrentLayout.subfolder(torrentName: "..", fileCount: 5))
        XCTAssertNil(TorrentLayout.subfolder(torrentName: "/", fileCount: 5))
        XCTAssertNil(TorrentLayout.subfolder(torrentName: "...", fileCount: 5))   // only dots
        XCTAssertNil(TorrentLayout.subfolder(torrentName: "---", fileCount: 5))   // only dashes after sanitize
        XCTAssertNil(TorrentLayout.subfolder(torrentName: ":", fileCount: 5))
    }

    func testNameCollapsesEverySeparatorKind() {
        // Every separator/NUL becomes '-' so the result is ONE path component.
        XCTAssertEqual(TorrentLayout.subfolder(torrentName: "a/b:c\u{0}d", fileCount: 2), "a-b-c-d")
    }

    // MARK: - Member-path safety (traversal guard)

    func testUnsafePathsRejected() {
        XCTAssertTrue(TorrentLayout.hasUnsafePath(["../etc/passwd"]))
        XCTAssertTrue(TorrentLayout.hasUnsafePath(["a/../../b"]))
        XCTAssertTrue(TorrentLayout.hasUnsafePath(["/absolute/path"]))
        XCTAssertTrue(TorrentLayout.hasUnsafePath(["dir/../x"]))
        XCTAssertTrue(TorrentLayout.hasUnsafePath(["nul\u{0}byte"]))
        XCTAssertTrue(TorrentLayout.hasUnsafePath([".."]))
        XCTAssertTrue(TorrentLayout.hasUnsafePath(["ok.txt", "../evil"]))  // any bad member taints the set
    }

    func testSafePathsAccepted() {
        XCTAssertFalse(TorrentLayout.hasUnsafePath(["Eng/ep1.srt", "movie.avi"]))
        XCTAssertFalse(TorrentLayout.hasUnsafePath(["a/b/c.iso"]))
        XCTAssertFalse(TorrentLayout.hasUnsafePath([]))
        XCTAssertFalse(TorrentLayout.hasUnsafePath(["..dots..in..name.txt"]))  // dots not a whole component
        XCTAssertFalse(TorrentLayout.hasUnsafePath(["a.b/c..d/e"]))            // '..' inside a name, not alone
        XCTAssertFalse(TorrentLayout.hasUnsafePath(["trailing/"]))            // trailing slash ⇒ empty comp, safe
    }

    // MARK: - Payload deletion probe (files removed from disk under the engine)

    func testSingleFileProbeIsTheFileItself() {
        // Single-file torrent writes straight into the chosen folder.
        XCTAssertEqual(
            TorrentLayout.payloadProbePaths(outputFolder: "/Users/x/Downloads", fileNames: ["Ubuntu.iso"]),
            ["/Users/x/Downloads/Ubuntu.iso"]
        )
    }

    func testMultiFileProbeIsTheWrapperFolder() {
        // Multi-file torrent is nested; the wrapper folder is the probe.
        XCTAssertEqual(
            TorrentLayout.payloadProbePaths(outputFolder: "/Users/x/Downloads/GoT S08", fileNames: ["ep1.mkv", "ep2.mkv"]),
            ["/Users/x/Downloads/GoT S08"]
        )
    }

    func testNoFileDetailYieldsNoProbe() {
        // Nothing to key off ⇒ never flag as missing.
        XCTAssertTrue(TorrentLayout.payloadProbePaths(outputFolder: "/Users/x/Downloads", fileNames: []).isEmpty)
    }

    func testMissingWhenSingleFileGone() {
        let missing = TorrentLayout.payloadMissing(
            outputFolder: "/dl", fileNames: ["movie.mkv"], exists: { _ in false })
        XCTAssertTrue(missing)
    }

    func testPresentWhenSingleFileExists() {
        let missing = TorrentLayout.payloadMissing(
            outputFolder: "/dl", fileNames: ["movie.mkv"], exists: { $0 == "/dl/movie.mkv" })
        XCTAssertFalse(missing)
    }

    func testMissingWhenWrapperFolderGone() {
        let missing = TorrentLayout.payloadMissing(
            outputFolder: "/dl/show", fileNames: ["a.mkv", "b.mkv"], exists: { _ in false })
        XCTAssertTrue(missing)
    }

    func testPresentWhenWrapperFolderExists() {
        let missing = TorrentLayout.payloadMissing(
            outputFolder: "/dl/show", fileNames: ["a.mkv", "b.mkv"], exists: { $0 == "/dl/show" })
        XCTAssertFalse(missing)
    }

    func testNoFileDetailNeverMissing() {
        // Empty file list ⇒ no probe ⇒ never reported missing, even if nothing exists.
        let missing = TorrentLayout.payloadMissing(
            outputFolder: "/dl", fileNames: [], exists: { _ in false })
        XCTAssertFalse(missing)
    }
}
