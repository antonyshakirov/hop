import XCTest
@testable import HopCore

/// Which release card the panel owes the user, and when it stops owing it.
final class ReleaseNewsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let card19 = ReleaseNews.Card(id: "1.9")

    // MARK: - Reading a version

    func testAVersionIsItsFirstTwoNumbers() {
        let version = ReleaseNews.Version("1.9.1")
        XCTAssertEqual(version?.major, 1)
        XCTAssertEqual(version?.minor, 9)
    }

    /// The whole point of dropping the third number: a fix rolled out on top of a
    /// release is still that release.
    func testAFixOnTopOfAReleaseIsTheSameRelease() {
        XCTAssertEqual(ReleaseNews.Version("1.9.1"), ReleaseNews.Version("1.9.0"))
    }

    func testTenComesAfterNine() {
        XCTAssertTrue(ReleaseNews.Version("1.9")! < ReleaseNews.Version("1.10")!)
    }

    func testANewMajorOutranksAnyMinor() {
        XCTAssertTrue(ReleaseNews.Version("1.99")! < ReleaseNews.Version("2.0")!)
    }

    func testSomethingThatIsNotAVersionIsRefused() {
        XCTAssertNil(ReleaseNews.Version("1"))
        XCTAssertNil(ReleaseNews.Version("dev"))
        XCTAssertNil(ReleaseNews.Version(""))
    }

    // MARK: - Which card

    func testTheCardForTheRunningReleaseIsShown() {
        XCTAssertEqual(ReleaseNews.visible([card19], installed: "1.9.1", now: now)?.id, "1.9")
    }

    /// Somebody already on 1.9.0 never saw this card, because it did not exist.
    func testSomebodyAlreadyOnTheReleaseStillGetsIt() {
        XCTAssertNotNil(ReleaseNews.visible([card19], installed: "1.9.0", now: now))
    }

    func testACardForAReleaseNotInstalledYetStaysQuiet() {
        let future = ReleaseNews.Card(id: "1.10")
        XCTAssertNil(ReleaseNews.visible([future], installed: "1.9.1", now: now))
    }

    /// A user who skipped a release wants to know where the app stands now, not
    /// to dismiss its history one card at a time.
    func testOnlyTheNewestCardIsShown() {
        let cards = [card19, ReleaseNews.Card(id: "1.10")]
        XCTAssertEqual(ReleaseNews.visible(cards, installed: "1.10.0", now: now)?.id, "1.10")
    }

    func testTheCardsItPassedOverAreReportedSoTheyCannotComeBack() {
        let cards = [card19, ReleaseNews.Card(id: "1.10")]
        XCTAssertEqual(ReleaseNews.overtaken(cards, installed: "1.10.0").map(\.id), ["1.9"])
    }

    func testAnUnreachableCardIsNotCountedAsOvertaken() {
        let cards = [card19, ReleaseNews.Card(id: "1.10")]
        XCTAssertTrue(ReleaseNews.overtaken(cards, installed: "1.9.1").isEmpty)
    }

    func testABuildWithoutAReadableVersionShowsNothing() {
        XCTAssertNil(ReleaseNews.visible([card19], installed: "dev", now: now))
    }

    // MARK: - How long it stands

    func testPressingAButtonEndsIt() {
        let seen = ReleaseNews.Card(id: "1.9", seen: true)
        XCTAssertNil(ReleaseNews.visible([seen], installed: "1.9.1", now: now))
    }

    func testItSurvivesItsFirstShowing() {
        let shown = ReleaseNews.Card(id: "1.9", shownCount: 1,
                                     firstShownAt: now.addingTimeInterval(-60))
        XCTAssertNotNil(ReleaseNews.visible([shown], installed: "1.9.1", now: now))
    }

    func testItLeavesAfterTwoOpenings() {
        let spent = ReleaseNews.Card(id: "1.9", shownCount: ReleaseNews.openings,
                                     firstShownAt: now.addingTimeInterval(-60))
        XCTAssertNil(ReleaseNews.visible([spent], installed: "1.9.1", now: now))
    }

    /// Somebody who neither reads nor dismisses it should not carry it at the top
    /// of the panel for the rest of the release.
    func testItLeavesAfterTwoDaysEvenUntouched() {
        let stale = ReleaseNews.Card(id: "1.9", shownCount: 1,
                                     firstShownAt: now.addingTimeInterval(-ReleaseNews.life))
        XCTAssertNil(ReleaseNews.visible([stale], installed: "1.9.1", now: now))
    }

    func testTwoDaysIsMeasuredFromTheFirstShowingNotFromInstalling() {
        let fresh = ReleaseNews.Card(id: "1.9", shownCount: 1,
                                     firstShownAt: now.addingTimeInterval(-ReleaseNews.life + 60))
        XCTAssertNotNil(ReleaseNews.visible([fresh], installed: "1.9.1", now: now))
    }

    func testACardNeverDrawnHasNotStartedItsClock() {
        XCTAssertNotNil(ReleaseNews.visible([card19], installed: "1.9.1", now: now))
    }
}
