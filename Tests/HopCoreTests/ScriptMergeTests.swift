import XCTest
@testable import HopCore

/// Repairing a line that carries two distant scripts at once — the one thing
/// Vision's own language detection cannot do, since it picks one model per line.
final class ScriptMergeTests: XCTestCase {

    private func fragment(_ text: String, x: Double, line: Int = 0) -> TextFragment {
        TextFragment(text: text, x: x, line: line)
    }

    // Cyrillic fixtures as escapes: the repo itself stays English-only,
    // while the strings it exercises are anything but.

    private let privet = "\u{041F}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442}"   // privet — hello
    private let mir = "\u{043C}\u{0438}\u{0440}"   // mir — world
    private let ofise = "\u{043E}\u{0444}\u{0438}\u{0441}\u{0435}"   // ofise — in the office
    private let vIn = "\u{0432}"   // v — in
    private let cyrillicRun = "\u{0431}\u{0431}\u{0431}\u{0431}\u{0431}"   // five Cyrillic be letters

    // MARK: - Scripts

    func testScriptsOfAWord() {
        XCTAssertEqual(ScriptMerge.scripts(in: "Hello"), [.latin])
        XCTAssertEqual(ScriptMerge.scripts(in: privet), [.cyrillic])
        XCTAssertEqual(ScriptMerge.scripts(in: "世界"), [.cjk])
        XCTAssertEqual(ScriptMerge.scripts(in: "미술관"), [.hangul])
        XCTAssertEqual(ScriptMerge.scripts(in: "متحف"), [.arabic])
        XCTAssertEqual(ScriptMerge.scripts(in: "ศิลปะ"), [.thai])
    }

    func testDigitsAndPunctuationBelongToNobody() {
        XCTAssertTrue(ScriptMerge.scripts(in: "15:00").isEmpty)
        XCTAssertTrue(ScriptMerge.scripts(in: "—").isEmpty)
        XCTAssertFalse(ScriptMerge.isGarbled("15:00"), "a time is not garbled")
    }

    func testAWordMixingScriptsIsGarbled() {
        // the real failure: a Cyrillic word read by a Japanese model
        XCTAssertTrue(ScriptMerge.isGarbled("门puBeT"))
        XCTAssertFalse(ScriptMerge.isGarbled(privet))
        XCTAssertFalse(ScriptMerge.isGarbled("Hello"))
    }

    // MARK: - Competence

    func testCompetenceRanksByHowMuchWasRead() {
        let fragments = [fragment("森美術館", x: 0), fragment("開館時間", x: 0.2),
                         fragment("Hello", x: 0.4)]
        XCTAssertEqual(ScriptMerge.dominant(of: fragments), .cjk)
        XCTAssertEqual(ScriptMerge.competence(of: fragments), [.cjk, .latin])
    }

    func testCompetenceStopsAtThreeScripts() {
        let fragments = [fragment("aaaa", x: 0), fragment(cyrillicRun, x: 0.1),
                         fragment("世界世界世", x: 0.2), fragment("미술관", x: 0.3),
                         fragment("متحف", x: 0.4)]
        XCTAssertEqual(ScriptMerge.competence(of: fragments).count, 3,
                       "past three it is noise, not a page")
    }

    // MARK: - Trigger

    func testOnlyLinesWithAGarbledWordAreSuspect() {
        let fragments = [fragment("Hello", x: 0.0, line: 0),
                         fragment("门puBeT", x: 0.2, line: 0),
                         fragment("متحف", x: 0.0, line: 1),
                         fragment("موري", x: 0.3, line: 1)]
        XCTAssertEqual(ScriptMerge.garbledLines(fragments), [0])
    }

    func testACleanPageNeedsNoSecondPass() {
        let fragments = [fragment("Mori", x: 0), fragment("Art", x: 0.2), fragment("Museum", x: 0.4)]
        XCTAssertTrue(ScriptMerge.garbledLines(fragments).isEmpty)
    }

    // MARK: - Helper languages

    func testHelperAsksForTheAlphabetsOnThePicture() {
        // the real case: a Japanese page with Russian and English on it. The CJK
        // model mangles the Cyrillic, so the helper must read alphabets — asking
        // it for Japanese would rescue nothing.
        let tags = ScriptMerge.helperLanguages(
            seen: [.cjk, .cyrillic, .latin], dominant: .latin, interface: .latin,
            supported: ["en-US", "ru-RU", "ja-JP"])
        XCTAssertEqual(tags, ["ru-RU", "en-US"])
        XCTAssertFalse(tags.contains("ja-JP"), "the first pass already read the ideographs")
    }

    func testHelperFallsBackToTheReadersScriptWhenThePageLeftNoTrace() {
        // a page whose Cyrillic was mangled so badly that no Cyrillic survived to
        // be seen: the reader's own language is the only hint left
        let tags = ScriptMerge.helperLanguages(
            seen: [.cjk], dominant: .cjk, interface: .cyrillic,
            supported: ["en-US", "ru-RU", "ja-JP"])
        XCTAssertEqual(tags, ["en-US", "ru-RU"])
    }

    func testHelperFallsBackToWhateverWasSeenWhenNoAlphabetIsPresent() {
        let tags = ScriptMerge.helperLanguages(
            seen: [.cjk], dominant: .cjk, interface: .cjk,
            supported: ["ja-JP"])
        XCTAssertEqual(tags, ["ja-JP"])
    }

    func testHelperDropsTagsThisMachineLacksAndStaysShort() {
        let tags = ScriptMerge.helperLanguages(
            seen: [.cjk, .cyrillic, .thai, .arabic], dominant: .cjk, interface: .latin,
            supported: ["ru-RU"], limit: 2)
        XCTAssertEqual(tags, ["ru-RU"], "an unsupported tag would fail the whole request")
    }

    func testHelperNeverAsksForMoreThanTheLimit() {
        let tags = ScriptMerge.helperLanguages(
            seen: [.cjk, .cyrillic, .thai, .arabic, .latin], dominant: .cjk, interface: .latin,
            supported: ["en-US", "ru-RU", "th-TH", "ar-SA", "ja-JP"], limit: 2)
        XCTAssertEqual(tags.count, 2, "many languages in one request make Vision worse")
    }

    // MARK: - Merge

    func testTheGarbledLineIsRepairedWordByWord() {
        // what Vision returns for a line of Latin, ideographs and two Cyrillic
        let primary = [fragment("Hello", x: 0.017), fragment("世界", x: 0.086),
                       fragment("门puBeT", x: 0.141), fragment("MMp", x: 0.238)]
        // words when it detects Japanese; then the same line read as Russian+English
        let helper = [fragment("Hello", x: 0.017), fragment("₩", x: 0.080),
                      fragment(privet, x: 0.139), fragment(mir, x: 0.236)]

        let merged = ScriptMerge.merge(primary: primary, helper: helper,
                                       helperCompetence: [.latin, .cyrillic])

        XCTAssertEqual(merged, ["Hello 世界 \(privet) \(mir)"])
    }

    func testACleanLineIsReturnedUntouchedAndKeepsItsOrder() {
        // right-to-left: sorting by x would reverse this, which is why order comes
        // from the first pass and never from the coordinate
        let primary = [fragment("متحف", x: 0.62), fragment("موري", x: 0.40),
                       fragment("للفنون", x: 0.10)]
        let helper = [fragment("wrong", x: 0.62), fragment("nonsense", x: 0.40)]

        let merged = ScriptMerge.merge(primary: primary, helper: helper,
                                       helperCompetence: [.latin, .cyrillic])

        XCTAssertEqual(merged, ["متحف موري للفنون"])
    }

    func testAWordTheHelperCannotReadIsKept() {
        let primary = [fragment("世界", x: 0.0), fragment("门puBeT", x: 0.2)]
        let helper = [fragment("₩", x: 0.0), fragment(privet, x: 0.2)]

        let merged = ScriptMerge.merge(primary: primary, helper: helper,
                                       helperCompetence: [.latin, .cyrillic])

        XCTAssertEqual(merged, ["世界 \(privet)"], "the currency sign is not a reading of the ideographs")
    }

    func testAWordWithNoTwinNearbyIsKept() {
        let primary = [fragment("门puBeT", x: 0.1)]
        let helper = [fragment(privet, x: 0.9)]   // far away: a different word

        let merged = ScriptMerge.merge(primary: primary, helper: helper,
                                       helperCompetence: [.latin, .cyrillic])

        XCTAssertEqual(merged, ["门puBeT"])
    }

    func testLinesKeepTheirOrder() {
        let primary = [fragment("one", x: 0, line: 0), fragment("two", x: 0, line: 1),
                       fragment("three", x: 0, line: 2)]
        XCTAssertEqual(ScriptMerge.merge(primary: primary, helper: [], helperCompetence: []),
                       ["one", "two", "three"])
    }
}
