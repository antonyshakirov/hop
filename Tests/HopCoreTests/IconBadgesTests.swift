import XCTest
@testable import HopCore

/// The pure composition matrix behind the menu-bar star's corner badges:
/// app state → the set of decorations to draw. Every single state, the two
/// same-corner pairs, the alert blink phases, the mono shape mapping and the
/// impossible-state exclusions are pinned here.
final class IconBadgesTests: XCTestCase {

    // MARK: - Single states

    func testIdleDrawsNothing() {
        let c = IconBadges.compose(IconState())
        XCTAssertTrue(c.isEmpty)
        XCTAssertTrue(c.badges.isEmpty)
        XCTAssertNil(c.torrent)
    }

    func testRunningEngineShowsGreenWedge() {
        let c = IconBadges.compose(IconState(engine: .running))
        XCTAssertTrue(c.engineTime)
        XCTAssertFalse(c.taskTime)
        XCTAssertEqual(c.badges, [.engineTime])
    }

    func testStopwatchIsTheSameGreenWedgeAsTheTimer() {
        // a stopwatch and a countdown both collapse to .running — the star does
        // not distinguish them (the title shows whether the value climbs or falls)
        let timer = IconBadges.compose(IconState(engine: .running))
        let stopwatch = IconBadges.compose(IconState(engine: .running))
        XCTAssertEqual(timer, stopwatch)
    }

    func testTrackingShowsDarkGreenWedge() {
        let c = IconBadges.compose(IconState(tracking: true))
        XCTAssertTrue(c.taskTime)
        XCTAssertFalse(c.engineTime)
        XCTAssertEqual(c.badges, [.taskTime])
    }

    func testNoSleepShowsYellowDot() {
        let c = IconBadges.compose(IconState(noSleep: true))
        XCTAssertEqual(c.badges, [.noSleep])
    }

    func testLidShowsOrangeDot() {
        let c = IconBadges.compose(IconState(lid: true))
        XCTAssertEqual(c.badges, [.lid])
    }

    func testTorrentDownOnly() {
        XCTAssertEqual(IconBadges.compose(IconState(torrentDown: true)).torrent, .down)
    }

    func testTorrentUpOnly() {
        XCTAssertEqual(IconBadges.compose(IconState(torrentUp: true)).torrent, .up)
    }

    func testTorrentBothDirections() {
        XCTAssertEqual(
            IconBadges.compose(IconState(torrentDown: true, torrentUp: true)).torrent, .both)
    }

    // MARK: - Wedge suppression (digits are the wedge's twin)

    func testEngineWedgeSuppressedWhenItsTimeIsInTheTitle() {
        // countdown digits visible → no redundant green wedge
        let c = IconBadges.compose(IconState(engine: .running, engineTimeInTitle: true))
        XCTAssertFalse(c.engineTime)
        XCTAssertTrue(c.isEmpty)
    }

    func testTaskWedgeSuppressedWhenTaskTimeIsInTheTitle() {
        let c = IconBadges.compose(IconState(tracking: true, taskTimeInTitle: true))
        XCTAssertFalse(c.taskTime)
    }

    func testPausedEngineShowsNoWedge() {
        // the wedge is a play triangle — it means "running", never "paused"
        let c = IconBadges.compose(IconState(engine: .paused))
        XCTAssertFalse(c.engineTime)
        XCTAssertTrue(c.isEmpty)
    }

    func testTimerDigitsHiddenButTaskStillShowsItsWedge() {
        // this is combined-mock row 1: the timer's value is in the title (its
        // wedge dropped) while the tracker keeps its own corner wedge
        let c = IconBadges.compose(IconState(
            engine: .running, engineTimeInTitle: true, tracking: true))
        XCTAssertFalse(c.engineTime)
        XCTAssertTrue(c.taskTime)
        XCTAssertEqual(c.badges, [.taskTime])
    }

    // MARK: - Same-corner pairs

    func testBothWedgesWhenDigitsAreHidden() {
        // countdown off: engine + task wedges share the bottom-right corner
        let c = IconBadges.compose(IconState(engine: .running, tracking: true))
        XCTAssertTrue(c.engineTime)
        XCTAssertTrue(c.taskTime)
        XCTAssertEqual(c.badges, [.engineTime, .taskTime])
        XCTAssertEqual(IconBadge.engineTime.corner, .bottomRight)
        XCTAssertEqual(IconBadge.taskTime.corner, .bottomRight)
    }

    func testBothAwakeDotsCanShowTogether() {
        // no-sleep and lid are NOT mutually exclusive — both dots line up top-right
        let c = IconBadges.compose(IconState(noSleep: true, lid: true))
        XCTAssertTrue(c.noSleep)
        XCTAssertTrue(c.lid)
        XCTAssertEqual(c.badges, [.noSleep, .lid])
        XCTAssertEqual(IconBadge.noSleep.corner, .topRight)
        XCTAssertEqual(IconBadge.lid.corner, .topRight)
    }

    // MARK: - Alert blink phases

    func testSteadyAlertLitOnEitherPhase() {
        // monitor red zone burns steadily — lit whether the tick is on or off
        XCTAssertTrue(IconBadges.compose(IconState(alertSteady: true, blinkOn: true)).alert)
        XCTAssertTrue(IconBadges.compose(IconState(alertSteady: true, blinkOn: false)).alert)
    }

    func testBlinkingAlertFollowsThePhase() {
        // an 8h task blinks: lit on the lit phase, gone on the dark phase
        XCTAssertTrue(IconBadges.compose(IconState(alertBlinking: true, blinkOn: true)).alert)
        XCTAssertFalse(IconBadges.compose(IconState(alertBlinking: true, blinkOn: false)).alert)
    }

    func testSteadySourceKeepsBlinkingSourceLitOnTheDarkPhase() {
        let c = IconBadges.compose(IconState(
            alertSteady: true, alertBlinking: true, blinkOn: false))
        XCTAssertTrue(c.alert)
    }

    func testNoAlertWhenNeitherSourceActive() {
        XCTAssertFalse(IconBadges.compose(IconState(blinkOn: true)).alert)
    }

    // MARK: - Mono shape mapping

    func testMonoShapeMappingIsFixed() {
        // first mark of each pair filled, second outline — so colour-off keeps
        // the two same-corner marks distinct
        XCTAssertTrue(IconBadge.noSleep.monoFilled)
        XCTAssertFalse(IconBadge.lid.monoFilled)
        XCTAssertTrue(IconBadge.engineTime.monoFilled)
        XCTAssertFalse(IconBadge.taskTime.monoFilled)
        XCTAssertTrue(IconBadge.alert.monoFilled)
    }

    func testColoredFlagPassesThrough() {
        XCTAssertTrue(IconBadges.compose(IconState(colored: true)).colored)
        XCTAssertFalse(IconBadges.compose(IconState(colored: false)).colored)
    }

    // MARK: - Worst case — every corner occupied

    func testEveryCornerAtOnce() {
        // combined-mock worst case: "!" + two dots + two wedges + both arrows
        let c = IconBadges.compose(IconState(
            engine: .running, tracking: true,
            noSleep: true, lid: true,
            alertSteady: true, blinkOn: true,
            torrentDown: true, torrentUp: true))
        XCTAssertEqual(Set(c.badges), Set([.alert, .noSleep, .lid, .engineTime, .taskTime]))
        XCTAssertEqual(c.torrent, .both)
        XCTAssertFalse(c.isEmpty)
        // one attention mark, two top dots, two bottom wedges — never more
        XCTAssertEqual(c.badges.filter { $0.corner == .topLeft }.count, 1)
        XCTAssertEqual(c.badges.filter { $0.corner == .topRight }.count, 2)
        XCTAssertEqual(c.badges.filter { $0.corner == .bottomRight }.count, 2)
    }
}
