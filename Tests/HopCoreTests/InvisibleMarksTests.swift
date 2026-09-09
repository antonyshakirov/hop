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

    func testTextWithoutInvisibleCharactersIsLeftAlone() {
        XCTAssertFalse(stray("save it to the desktop", rightToLeft: false))
        XCTAssertFalse(stray("שמירה במחשב"))
        XCTAssertFalse(stray("", rightToLeft: false))
    }
}
