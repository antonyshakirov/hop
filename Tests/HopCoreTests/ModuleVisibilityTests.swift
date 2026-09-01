import XCTest
@testable import HopCore

/// The torrent row came back on a panel where it had been switched off, right
/// after an update. The rule had a second, invisible condition — the engine's
/// installer state — so the user's answer only held while that state happened to
/// be exactly "installed".
final class ModuleVisibilityTests: XCTestCase {

    private func visible(
        _ module: String,
        hidden: Set<String> = [],
        torrents: Int = 0,
        showWhenEmpty: Bool = true
    ) -> Bool {
        ModuleVisibility.isVisible(
            module: module, hidden: hidden,
            torrentCount: torrents, showTorrentWhenEmpty: showWhenEmpty)
    }

    func testHiddenModulesNeverShow() {
        XCTAssertFalse(visible("timer", hidden: ["timer", "color"]))
        XCTAssertFalse(visible("torrent", hidden: ["torrent"], torrents: 3))
    }

    func testShownModulesShow() {
        XCTAssertTrue(visible("timer", hidden: ["color"]))
    }

    func testEmptyTorrentRowHidesWhenAsked() {
        XCTAssertFalse(visible("torrent", torrents: 0, showWhenEmpty: false))
    }

    func testEmptyTorrentRowStaysWhenWanted() {
        XCTAssertTrue(visible("torrent", torrents: 0, showWhenEmpty: true))
    }

    /// A download in progress outranks the preference: the row is where its
    /// progress lives.
    func testTorrentsPresentAlwaysShow() {
        XCTAssertTrue(visible("torrent", torrents: 1, showWhenEmpty: false))
    }

    /// The regression itself: the answer must not depend on anything but the
    /// three inputs. There is no engine state to pass in any more, so a fresh
    /// launch, a download in flight and a failed fetch all give one answer.
    func testTheAnswerDependsOnNothingElse() {
        for _ in 0..<3 {
            XCTAssertFalse(visible("torrent", torrents: 0, showWhenEmpty: false))
        }
    }

    func testOtherModulesIgnoreTheTorrentPreference() {
        XCTAssertTrue(visible("archive", torrents: 0, showWhenEmpty: false))
    }
}
