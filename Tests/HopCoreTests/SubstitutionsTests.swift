import XCTest
@testable import HopCore

final class SubstitutionsTests: XCTestCase {
    private func bare(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !(0x2066...0x2069).contains($0.value)
        }))
    }

    func testEachValueGoesWhereTheSentenceNumbersIt() {
        XCTAssertEqual(bare(Substitutions.fill("%1$@ of %2$@ files", ["4", "6"])), "4 of 6 files")
    }

    func testASentenceMayNumberItsValuesInAnyOrder() {
        XCTAssertEqual(bare(Substitutions.fill("%2$@ free, %1$@ needed", ["14 GB", "208 GB"])),
                       "208 GB free, 14 GB needed")
    }

    func testTheSameValueMayBeAskedForTwice() {
        XCTAssertEqual(bare(Substitutions.fill("%1$@ – %1$@", ["hop"])), "hop – hop")
    }

    func testEveryValueIsFencedOffFromTheSentence() {
        XCTAssertEqual(Substitutions.fill("in %1$@ now", ["Downloads"]),
                       "in \u{2068}Downloads\u{2069} now")
    }

    func testAFigureTheSentenceCarriesIsNotAPlaceNumber() {
        XCTAssertEqual(bare(Substitutions.fill("about ~%80 of it", ["a"])), "about ~%80 of it")
        XCTAssertEqual(bare(Substitutions.fill("progress 100%1 done", ["a"])), "progress 100%1 done")
    }

    func testAPlaceNumberWithNoValueBehindItPrintsItself() {
        XCTAssertEqual(bare(Substitutions.fill("%3$@ of %1$@", ["a", "b"])), "%3$@ of a")
    }

    func testAPlaceNumberedFromZeroPrintsItself() {
        XCTAssertEqual(bare(Substitutions.fill("%0$@ x", ["a"])), "%0$@ x")
    }

    func testASubstitutionSpeltWrongPrintsItself() {
        XCTAssertEqual(bare(Substitutions.fill("%1$d free", ["a"])), "%1$d free")
        XCTAssertEqual(bare(Substitutions.fill("%1@ free", ["a"])), "%1@ free")
        XCTAssertEqual(bare(Substitutions.fill("%$@ free", ["a"])), "%$@ free")
    }

    func testAPerCentSignAtTheVeryEndIsLeftAlone() {
        XCTAssertEqual(bare(Substitutions.fill("cpu %", ["a"])), "cpu %")
        XCTAssertEqual(bare(Substitutions.fill("100%% sure", ["a"])), "100%% sure")
    }

    func testAPlaceNumberTooLongToCountDoesNotOverflow() {
        let long = "%" + String(repeating: "9", count: 40) + "$@ free"
        XCTAssertEqual(bare(Substitutions.fill(long, ["a"])), long)
    }

    func testOnlyPlainFiguresCountAsAPlaceNumber() {
        XCTAssertEqual(bare(Substitutions.fill("%\u{0661}$@ free", ["a"])), "%\u{0661}$@ free")
        XCTAssertEqual(bare(Substitutions.fill("%\u{06F1}$@ free", ["a"])), "%\u{06F1}$@ free")
    }

    func testNothingGivenLeavesTheSentenceWhole() {
        XCTAssertEqual(bare(Substitutions.fill("%1$@ of %2$@", [])), "%1$@ of %2$@")
    }

    func testASentenceWithOneValueTakesItAtThePerCentAt() {
        XCTAssertEqual(bare(Substitutions.fill("version %@ is out", "2.1.0")), "version 2.1.0 is out")
    }

    func testAValueThatWouldCloseOurFenceIsStrippedOfIt() {
        let out = Substitutions.isolate("2.5.0\u{2069}\u{202E}gnp.exe")
        XCTAssertEqual(out, "\u{2068}2.5.0gnp.exe\u{2069}")
    }

    func testAValueKeepsEverythingThatIsNotADirectionControl() {
        XCTAssertEqual(Substitutions.isolate("سلام hop.zip"), "\u{2068}سلام hop.zip\u{2069}")
    }

    func testAValueStrippedOfItsControlsIsWhatTheFenceHolds() {
        XCTAssertEqual(Substitutions.plain("invoice\u{202E}fdp.exe"), "invoicefdp.exe")
        XCTAssertEqual(Substitutions.plain("\u{2066}\u{2069}"), "")
        XCTAssertEqual(Substitutions.plain("hop.zip"), "hop.zip")
        XCTAssertEqual(Substitutions.isolate("a\u{202E}b"),
                       "\u{2068}" + Substitutions.plain("a\u{202E}b") + "\u{2069}")
    }

    func testTheFenceSurvivesALineTheValueBreaks() {
        for end in ["\n", "\r", "\r\n", "\u{000B}", "\u{000C}", "\u{0085}",
                    "\u{2028}", "\u{2029}"] {
            XCTAssertEqual(Substitutions.plain("a\(end)b"), "a b",
                           end.unicodeScalars.map(\.value).description)
        }
        XCTAssertEqual(Substitutions.isolate("a\u{2029}b"), "\u{2068}a b\u{2069}")
    }

    func testAValueLeftWithNothingToReadFallsBackToTheNameWeKnow() {
        XCTAssertEqual(Substitutions.isolate("\u{202E}\u{2069}", or: "apps"), "apps")
        XCTAssertEqual(Substitutions.isolate("   ", or: "apps"), "apps")
        XCTAssertEqual(Substitutions.isolate("", or: "apps"), "apps")
        XCTAssertEqual(Substitutions.isolate("  Games  ", or: "apps"),
                       "\u{2068}Games\u{2069}")
        XCTAssertEqual(Substitutions.isolate("a\u{202E}b", or: "apps"),
                       "\u{2068}ab\u{2069}")
    }

    func testAValueKeepsTheSpacesItCameWith() {
        XCTAssertEqual(Substitutions.plain(" 5.1 GB "), " 5.1 GB ")
    }

    func testASentenceCarriesTheSubstitutionsItIsWrittenWith() {
        XCTAssertEqual(Substitutions.all("%1$@ of %2$@ · {n}"), ["%1$@", "%2$@", "{n}"])
        XCTAssertEqual(Substitutions.all("{sym:gear} settings %@"), ["%@", "{sym:gear}"])
    }

    func testTwoSentencesCarryTheSameOnesWhateverOrderTheyPutThemIn() {
        XCTAssertEqual(Substitutions.all("%1$@ of %2$@"), Substitutions.all("%2$@ من %1$@"))
    }

    func testAPerCentSignThatOpensNothingIsNotASubstitution() {
        XCTAssertEqual(Substitutions.all("about ~%80 of cpu %"), [])
    }

    func testABraceLeftOpenIsNotASubstitution() {
        XCTAssertEqual(Substitutions.all("{n files"), [])
    }
}
