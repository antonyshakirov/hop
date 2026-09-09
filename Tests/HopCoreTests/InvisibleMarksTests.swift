import XCTest
@testable import HopCore

/// A left-to-right table carries no invisible character at all. A right-to-left
/// one may carry four: the non-joiner Persian spelling needs, and the three
/// marks that steer a Latin fragment, a number or a key chord inside a line
/// that runs the other way.
final class InvisibleMarksTests: XCTestCase {
    private let zwnj = "\u{200C}"
    private let lrm = "\u{200E}"
    private let rlm = "\u{200F}"
    private let alm = "\u{061C}"
    private let nb = "\u{00A0}"

    private func stray(_ text: String, rightToLeft: Bool = true) -> Bool {
        InvisibleMarks.stray(text, rightToLeft: rightToLeft)
    }

    func testANonJoinerBetweenTwoLettersHoldsThemApart() {
        XCTAssertFalse(stray("می\(zwnj)شود"))
    }

    func testANonJoinerInFrontOfAPlaceholderHoldsItApart() {
        XCTAssertFalse(stray("ه\(zwnj)%@ باز"))
    }

    func testANonJoinerInFrontOfANumberHoldsItApart() {
        XCTAssertFalse(stray("می\(zwnj)۲"))
    }

    func testANonJoinerAtTheStartHoldsNothingApart() {
        XCTAssertTrue(stray("\(zwnj)شود"))
    }

    func testANonJoinerBesideAnyKindOfSpaceHoldsNothingApart() {
        XCTAssertTrue(stray("می \(zwnj)شود"))
        XCTAssertTrue(stray("می\(zwnj) شود"))
        XCTAssertTrue(stray("می\(nb)\(zwnj)شود"))
        XCTAssertTrue(stray("می\n\(zwnj)شود"))
        XCTAssertTrue(stray("می\t\(zwnj)شود"))
    }

    func testASecondNonJoinerAgainstTheFirstHoldsNothingApart() {
        XCTAssertTrue(stray("می\(zwnj)\(zwnj)شود"))
    }

    func testANonJoinerAtTheEndHoldsNothingApart() {
        XCTAssertTrue(stray("می\(zwnj)"))
    }

    func testADirectionMarkSteersALatinFragment() {
        XCTAssertFalse(stray("پرونده \(lrm)Hop باز"))
    }

    func testADirectionMarkSteersAFragmentOpeningOnPunctuation() {
        XCTAssertFalse(stray("فایل \(lrm).torrent"))
    }

    func testADirectionMarkSteersANonAsciiLatinFragment() {
        XCTAssertFalse(stray("فایل \(lrm)Ćao"))
    }

    func testAPairOfMarksAroundALatinFragmentBothSteer() {
        XCTAssertFalse(stray("فایل \(lrm)Hop\(lrm) باز"))
        XCTAssertFalse(stray("برنامه Hop\(rlm) باز"))
    }

    func testADirectionMarkSteersAChord() {
        XCTAssertFalse(stray("\(rlm)⌘\(nb)V"))
    }

    func testADirectionMarkSteersAChordAcrossANoBreakSpace() {
        XCTAssertFalse(stray("\(rlm)\(nb)⌘\(nb)V"))
    }

    func testAnArabicLetterMarkSteersANumber() {
        XCTAssertFalse(stray("صفحه \(alm)12"))
    }

    func testADirectionMarkInFrontOfARightToLeftLetterSteersNothing() {
        XCTAssertTrue(stray("\(rlm)מנוע"))
        XCTAssertTrue(stray("\(lrm)مرورگر"))
    }

    func testADirectionMarkBetweenTwoSpacesSteersNothing() {
        XCTAssertTrue(stray("باز \(lrm) Hop"))
    }

    func testADirectionMarkBetweenARightToLeftWordAndPunctuationSteersNothing() {
        XCTAssertTrue(stray("باز\(lrm)."))
    }

    func testADirectionMarkAtTheEndOfARightToLeftWordSteersNothing() {
        XCTAssertTrue(stray("Hop باز\(rlm)"))
    }

    func testTheSecondMarkIsWeighedAsWellAsTheFirst() {
        XCTAssertTrue(stray("\(lrm)Hop باز\(lrm)"))
    }

    func testALineRunningLeftToRightCarriesNoInvisibleCharacterAtAll() {
        XCTAssertTrue(stray("co\(zwnj)py", rightToLeft: false))
        XCTAssertTrue(stray("\(rlm)5 + 9 = 14", rightToLeft: false))
        XCTAssertTrue(stray("\(alm)12 34", rightToLeft: false))
        XCTAssertTrue(stray("press \(lrm)⌘\(nb)V", rightToLeft: false))
    }

    func testAnInvisibleCharacterTheTablesNeverUseIsRefused() {
        for scalar in ["\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                       "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
                       "\u{200B}", "\u{FEFF}", "\u{2060}", "\u{00AD}",
                       "\u{3164}", "\u{FE0F}", "\u{2028}"] {
            XCTAssertTrue(stray("باز\(scalar)Hop"), scalar.unicodeScalars.map(\.value).description)
        }
    }

    func testTheMarkIsReportedWithWhereItStands() {
        let found = InvisibleMarks.strayMark("باز \u{202E}Hop", rightToLeft: true)
        XCTAssertEqual(found?.offset, 4)
        XCTAssertEqual(found?.scalar.value, 0x202E)
        XCTAssertNil(InvisibleMarks.strayMark("باز Hop", rightToLeft: true))
    }

    func testAMarkAtTheHeadOfALineTurnsTheWholeLineRound() {
        XCTAssertFalse(stray("\(rlm)vpn מופעל"))
        XCTAssertFalse(stray("\(rlm)zip · rar بایگانی"))
    }

    func testAMarkTurnsTheLineItStandsOnAndNoOther() {
        XCTAssertFalse(stray("מנוע\n\(rlm)vpn פתוח"))
        XCTAssertTrue(stray("vpn פתוח\n\(rlm)מנוע"))
    }

    func testAMarkStandingAfterTheFirstLetterTurnsNothing() {
        XCTAssertTrue(stray("מנוע \(rlm) vpn"))
    }

    func testALineOpeningOnALatinWordIsFound() {
        XCTAssertEqual(InvisibleMarks.openingLeftToRight("vpn מופעל"), "vpn מופעל")
        XCTAssertEqual(InvisibleMarks.openingLeftToRight("מופעל\nmd ← pdf המרה"), "md ← pdf המרה")
    }

    func testALineTurnedRoundByAMarkOpensTheRightWay() {
        XCTAssertNil(InvisibleMarks.openingLeftToRight("\(rlm)vpn מופעל"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("מופעל vpn"))
    }

    func testALineWithNoRightToLeftLetterHasNothingToTurn() {
        XCTAssertNil(InvisibleMarks.openingLeftToRight("Kbps"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("cpu %"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("wi-fi: guest-4821"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("5.1 GB"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight(""))
    }

    func testAMarkOnALineWithNothingToTurnIsStray() {
        XCTAssertTrue(stray("\(rlm)cpu %"))
        XCTAssertTrue(stray("\(rlm)Downloads"))
        XCTAssertTrue(stray("\(rlm)hop.tools 1.2.3"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("\(rlm)cpu %"))
    }

    func testEveryFormatLetterIsSteppedOver() {
        for letter in ["@", "d", "s", "c", "f", "g", "x", "p", "e", "o"] {
            XCTAssertNil(InvisibleMarks.openingLeftToRight("%\(letter) עברית"), letter)
        }
        XCTAssertNil(InvisibleMarks.openingLeftToRight("%% עברית"))
        XCTAssertNotNil(InvisibleMarks.openingLeftToRight("cpu עברית"))
    }

    func testAWidthAPrecisionAndAPlaceNumberAreStillOneSubstitution() {
        XCTAssertNil(InvisibleMarks.openingLeftToRight("%.1f עברית"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("%-5d עברית"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("%1$@ עברית"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("%2$04X עברית"))
    }

    func testWhatOpensNoSubstitutionIsReadAsItStands() {
        XCTAssertNotNil(InvisibleMarks.openingLeftToRight("50% of עברית"))
        XCTAssertNotNil(InvisibleMarks.openingLeftToRight("{beta עברית"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("עברית %"))
    }

    func testALineEndsAtEveryLineBreakTheSame() {
        for end in ["\n", "\r", "\r\n", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}"] {
            XCTAssertEqual(InvisibleMarks.openingLeftToRight("עברית\(end)vpn עברית"), "vpn עברית",
                           "a line ending in \(end.unicodeScalars.map { $0.escaped(asASCII: true) })")
        }
    }

    func testAMarkThatWouldTurnALineTheWrongWayIsNoWork() {
        XCTAssertNotNil(InvisibleMarks.openingLeftToRight("\(lrm)vpn עברית"))
    }

    func testAMarkBesideSomethingThatOnlyLooksLikeASubstitutionIsStray() {
        XCTAssertTrue(stray("מונה \(lrm)% הושלם"))
        XCTAssertTrue(stray("משהו \(lrm){לא סגור"))
        XCTAssertFalse(stray("מונה \(lrm)%@ הושלם"))
        XCTAssertFalse(stray("מונה \(lrm){n} הושלם"))
        XCTAssertFalse(stray("מונה %@\(lrm) הושלם"))
    }

    /// A brace another opens before it closes is not a substitution, so it
    /// cannot reach past the real one standing after it and take the line's
    /// first strong letter with it.
    func testABraceInsideABraceReachesNoFurtherThanItsOwn() {
        XCTAssertEqual(InvisibleMarks.openingLeftToRight("{a{n} עברית"), "{a{n} עברית")
        XCTAssertNil(InvisibleMarks.openingLeftToRight("{n} עברית"))
    }

    func testAnIsolateLeftOpenIsCaughtAsAStrayMark() {
        XCTAssertTrue(stray("\u{2067}vpn עברית"))
    }

    func testASubstitutionCarriesItsOwnDirectionAndCountsForNothing() {
        XCTAssertNil(InvisibleMarks.openingLeftToRight("%@ מופעל"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("%1$ld מתוך %2$ld"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("{sym:gear} הגדרות"))
        XCTAssertNil(InvisibleMarks.openingLeftToRight("{n} דקות"))
        XCTAssertEqual(InvisibleMarks.openingLeftToRight("%@ vpn מופעל"), "%@ vpn מופעל")
    }

    func testWhatAnIsolateHoldsIsSteppedOverWhole() {
        XCTAssertNil(InvisibleMarks.openingLeftToRight("\u{2068}Hop\u{2069} מופעל"))
    }

    func testTextWithoutInvisibleCharactersIsLeftAlone() {
        XCTAssertFalse(stray("save it to the desktop", rightToLeft: false))
        XCTAssertFalse(stray("שמירה במחשב"))
        XCTAssertFalse(stray("", rightToLeft: false))
    }
}
