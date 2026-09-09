import XCTest
@testable import HopCore

/// The rule is the same in every language, so it is tested in the one this
/// repository is written in. Which words each language counts as short, and
/// which lean back, is data rather than logic: it lives in L10n.shortWords and
/// L10n.trailingWords and is guarded by `--l10n-check`.
final class HangingWordsTests: XCTestCase {
    private let nb = "\u{00A0}"
    private let words: Set<String> = ["a", "i", "of", "to", "in", "on"]
    private let leaning: Set<String> = ["though"]

    func testAShortWordIsJoinedToTheWordAfterIt() {
        XCTAssertEqual(HangingWords.glued("captions on a screen", shortWords: words),
                       "captions on\(nb)a\(nb)screen")
    }

    func testTheLastWordHasNothingToJoinTo() {
        XCTAssertEqual(HangingWords.glued("save it to", shortWords: words), "save it to")
    }

    func testAJoinStopsBeforeTheRunGetsTooLong() {
        XCTAssertEqual(HangingWords.glued("point to videoconferencing", shortWords: words),
                       "point to videoconferencing")
    }

    func testARunPastTheLimitIsTakenBackApart() {
        XCTAssertEqual(HangingWords.glued("point to\(nb)videoconferencing", shortWords: words),
                       "point to videoconferencing")
    }

    func testAChainOfShortWordsIsJoinedWhileItStaysShort() {
        XCTAssertEqual(HangingWords.glued("drag it in to a box", shortWords: words),
                       "drag it in\(nb)to\(nb)a\(nb)box")
    }

    func testAPlaceholderIsNeverJoined() {
        XCTAssertEqual(HangingWords.glued("saved to %@", shortWords: words),
                       "saved to %@")
    }

    func testANumberedPlaceholderIsNeverJoined() {
        XCTAssertEqual(HangingWords.glued("%1$@ of %2$@ files", shortWords: words),
                       "%1$@ of %2$@ files")
    }

    func testALineBreakStartsTheRunAgain() {
        XCTAssertEqual(HangingWords.glued("a window\nin a frame", shortWords: words),
                       "a\(nb)window\nin\(nb)a\(nb)frame")
    }

    func testAQuotedShortWordCountsAllTheSame() {
        XCTAssertEqual(HangingWords.glued("press \"a\" twice", shortWords: words),
                       "press \"a\" twice")
        XCTAssertEqual(HangingWords.glued("press \"a screen\"", shortWords: words),
                       "press \"a\(nb)screen\"")
    }

    func testAShortWordCarryingPunctuationIsLeftAlone() {
        XCTAssertEqual(HangingWords.glued("one (or two, i) then three", shortWords: words),
                       "one (or two, i) then three")
    }

    func testAnElidedShortWordIsFound() {
        XCTAssertEqual(HangingWords.glued("l'a fait", shortWords: ["a"]), "l'a\(nb)fait")
    }

    func testAWordIsNotJoinedToADash() {
        XCTAssertEqual(HangingWords.glued("in – one button", shortWords: words),
                       "in – one button")
    }

    func testAKeyChordHoldsTogether() {
        XCTAssertEqual(HangingWords.glued("press ⌃ ⌥ M twice", shortWords: []),
                       "press ⌃\(nb)⌥\(nb)M twice")
    }

    func testAChordKeepsItsDirectionMark() {
        XCTAssertEqual(HangingWords.glued("\u{200F}⌘ V", shortWords: []), "\u{200F}⌘\(nb)V")
    }

    func testALeaningParticleIsJoinedBackwards() {
        XCTAssertEqual(HangingWords.glued("it works though it is slow",
                                          shortWords: words, trailing: leaning),
                       "it works\(nb)though it is slow")
    }

    func testALeaningParticleGluedForwardIsTurnedAround() {
        XCTAssertEqual(HangingWords.glued("it works though\(nb)it is slow",
                                          shortWords: words, trailing: leaning),
                       "it works\(nb)though it is slow")
    }

    func testAnEmptyWordSetChangesNothing() {
        XCTAssertEqual(HangingWords.glued("ein fenster in der mitte", shortWords: []),
                       "ein fenster in der mitte")
    }

    func testAJoinTheRuleDoesNotOwnIsLeftInPlace() {
        XCTAssertEqual(HangingWords.glued("nur\(nb)ein fenster", shortWords: []),
                       "nur\(nb)ein fenster")
    }

    func testGluingTwiceChangesNothing() {
        let once = HangingWords.glued("captions on a screen, and a frame",
                                      shortWords: words, trailing: leaning)
        XCTAssertEqual(HangingWords.glued(once, shortWords: words, trailing: leaning), once)
    }

    func testAChordPressedAgainstASentenceHoldsTogether() {
        XCTAssertEqual(HangingWords.glued("opens,⌃ ⌥ M here", shortWords: []),
                       "opens,⌃\(nb)⌥\(nb)M here")
    }

    func testAChordAgainstALongWordStartsItsOwnRun() {
        XCTAssertEqual(HangingWords.glued("videoconferencing⌃ V", shortWords: []),
                       "videoconferencing⌃\(nb)V")
    }

    func testAShortWordIsJoinedToANumber() {
        XCTAssertEqual(HangingWords.glued("in 5 minutes", shortWords: words),
                       "in\(nb)5\(nb)minutes")
    }

    func testAJoinCarriesOnThroughWhatIsNotAWord() {
        XCTAssertEqual(HangingWords.glued("speed of ↑ upload", shortWords: words),
                       "speed of\(nb)↑\(nb)upload")
    }

    func testACountPlaceholderIsNeverJoined() {
        XCTAssertEqual(HangingWords.glued("set to {n} min", shortWords: words),
                       "set to {n} min")
    }

    func testASymbolPlaceholderIsNeverJoined() {
        XCTAssertEqual(HangingWords.glued("open a {sym:gear} panel", shortWords: words),
                       "open a {sym:gear} panel")
    }

    func testALeaningParticleCarryingACommaIsStillJoined() {
        XCTAssertEqual(HangingWords.glued("the same though, and more",
                                          shortWords: words, trailing: leaning),
                       "the same\(nb)though, and more")
    }

    func testALeaningParticleCostsOnlyItsOwnLength() {
        XCTAssertEqual(HangingWords.glued("videoconferencing though",
                                          shortWords: words, trailing: leaning),
                       "videoconferencing\(nb)though")
    }

    func testAHandJoinAfterAShortWordCarryingPunctuationSurvives() {
        XCTAssertEqual(HangingWords.glued("in,\(nb)and out", shortWords: words),
                       "in,\(nb)and out")
    }

    func testAChordAgainstASpacelessSentenceKeepsItsKey() {
        XCTAssertEqual(HangingWords.glued("⌃ ⌥ M。verylongsentencewithoutanyspaces",
                                          shortWords: []),
                       "⌃\(nb)⌥\(nb)M。verylongsentencewithoutanyspaces")
    }

    func testTheSpaceAfterAChordsKeyIsTheRulesToTakeApart() {
        XCTAssertEqual(HangingWords.glued("press ⌘ V\(nb)also here", shortWords: []),
                       "press ⌘\(nb)V also here")
    }

    func testGluingTwiceChangesNothingThroughANumber() {
        let once = HangingWords.glued("in 5 and 10 minutes", shortWords: words)
        XCTAssertEqual(once, "in\(nb)5\(nb)and 10 minutes")
        XCTAssertEqual(HangingWords.glued(once, shortWords: words), once)
    }

    func testTheCarryStopsAtAComma() {
        XCTAssertEqual(HangingWords.glued("meet in 14:30, room 4", shortWords: words),
                       "meet in\(nb)14:30, room 4")
    }

    func testACarryPastACommaIsTakenBackOut() {
        XCTAssertEqual(HangingWords.glued("meet in\(nb)14:30,\(nb)room 4", shortWords: words),
                       "meet in\(nb)14:30, room 4")
    }

    func testALeaningParticleHoldsOnPastAPlaceholder() {
        XCTAssertEqual(HangingWords.glued("%@ though it works",
                                          shortWords: words, trailing: leaning),
                       "%@\(nb)though it works")
    }

    func testAPrintfNumberIsNeverJoinedTo() {
        XCTAssertEqual(HangingWords.glued("saved to %ld files", shortWords: words),
                       "saved to %ld files")
    }

    func testARunReachesTheLimitButNotPastIt() {
        let fits = String(repeating: "b", count: HangingWords.runLimit - 2)
        XCTAssertEqual(HangingWords.glued("a " + fits, shortWords: words),
                       "a\(nb)" + fits)
        XCTAssertEqual(HangingWords.glued("a " + fits + "b", shortWords: words),
                       "a " + fits + "b")
    }

    func testADirectionMarkDoesNotHideAShortWord() {
        XCTAssertEqual(HangingWords.glued("\u{200F}of top", shortWords: words),
                       "\u{200F}of\(nb)top")
    }

    func testABrokenChordIsFoundInTheTextItself() {
        XCTAssertTrue(HangingWords.chordBreaks("press ⌃\(nb)⌥ M"))
        XCTAssertFalse(HangingWords.chordBreaks("press ⌃\(nb)⌥\(nb)M"))
        XCTAssertFalse(HangingWords.chordBreaks("press it twice"))
    }

    func testTextWithNothingToJoinIsReturnedWhole() {
        XCTAssertEqual(HangingWords.glued("", shortWords: words), "")
        XCTAssertEqual(HangingWords.glued("word", shortWords: words), "word")
        XCTAssertEqual(HangingWords.glued(" ", shortWords: words), " ")
    }

    func testNormalizingTakesAChordApartAndLeavesAHandJoinAlone() {
        XCTAssertEqual(HangingWords.normalized("⌘\(nb)V", shortWords: []), "⌘ V")
        XCTAssertEqual(HangingWords.normalized("works\(nb)though",
                                               shortWords: words, trailing: leaning),
                       "works though")
        XCTAssertEqual(HangingWords.normalized("nur\(nb)ein", shortWords: []), "nur\(nb)ein")
    }

    func testNormalizingTakesTheRulesOwnJoinsBackOut() {
        XCTAssertEqual(HangingWords.normalized("captions on\(nb)a\(nb)screen", shortWords: words),
                       "captions on a screen")
    }
}
