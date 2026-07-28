import XCTest
@testable import HopCore

/// Parsing the command file an outside agent writes. The writer is a language
/// model or a hand-edited file, so the parser is forgiving by design: one bad
/// entry must not discard the rest, and an unknown verb must not be an error.
final class AgentCommandTests: XCTestCase {

    private func parse(_ json: String) -> [AgentCommand] {
        AgentCommandParser.parse(Data(json.utf8))
    }

    // MARK: - Shape

    func testParsesTheDocumentedShape() {
        let out = parse(#"{"commands":[{"do":"timer.start","minutes":16}]}"#)
        XCTAssertEqual(out, [.timerStart(seconds: 960)])
    }

    func testParsesABareArrayToo() {
        let out = parse(#"[{"do":"timer.pause"}]"#)
        XCTAssertEqual(out, [.timerPause])
    }

    func testAcceptsCommandAndActionAsTheVerbKey() {
        XCTAssertEqual(parse(#"[{"command":"timer.reset"}]"#), [.timerReset])
        XCTAssertEqual(parse(#"[{"action":"stopwatch.start"}]"#), [.stopwatchStart])
    }

    func testGarbageYieldsNothingRatherThanThrowing() {
        XCTAssertEqual(parse("not json at all"), [])
        XCTAssertEqual(parse("{}"), [])
        XCTAssertEqual(parse("[]"), [])
    }

    func testOneBadEntryDoesNotDiscardTheRest() {
        let out = parse("""
        {"commands":[{"do":"nonsense.verb"},{"do":"timer.start","minutes":5},{"do":"timer.pause"}]}
        """)
        XCTAssertEqual(out, [.timerStart(seconds: 300), .timerPause])
    }

    // MARK: - Durations

    func testDurationAcceptsEveryReasonableSpelling() {
        XCTAssertEqual(AgentCommandParser.duration(from: "16m"), 960)
        XCTAssertEqual(AgentCommandParser.duration(from: "90s"), 90)
        XCTAssertEqual(AgentCommandParser.duration(from: "1h30m"), 5400)
        XCTAssertEqual(AgentCommandParser.duration(from: "2h"), 7200)
        XCTAssertEqual(AgentCommandParser.duration(from: "25:00"), 1500)
        XCTAssertEqual(AgentCommandParser.duration(from: "1:05:30"), 3930)
        XCTAssertEqual(AgentCommandParser.duration(from: "16"), 960, "a bare number means minutes")
    }

    func testDurationRejectsNonsense() {
        XCTAssertNil(AgentCommandParser.duration(from: ""))
        XCTAssertNil(AgentCommandParser.duration(from: "soon"))
        XCTAssertNil(AgentCommandParser.duration(from: "0m"))
    }

    func testTimerAcceptsSecondsMinutesHoursOrADurationString() {
        XCTAssertEqual(parse(#"[{"do":"timer.start","seconds":45}]"#), [.timerStart(seconds: 45)])
        XCTAssertEqual(parse(#"[{"do":"timer.start","hours":1}]"#), [.timerStart(seconds: 3600)])
        XCTAssertEqual(parse(#"[{"do":"timer","duration":"16m"}]"#), [.timerStart(seconds: 960)])
    }

    func testTimerWithoutAUsableDurationIsSkipped() {
        XCTAssertEqual(parse(#"[{"do":"timer.start"}]"#), [])
        XCTAssertEqual(parse(#"[{"do":"timer.start","minutes":0}]"#), [])
    }

    // MARK: - To-dos

    func testTodoAddCarriesEveryField() {
        let out = parse("""
        {"commands":[{"do":"todo.add","text":"  call the notary  ","note":"ask for the copy",
        "remindAt":"2026-07-28T15:00:00Z","repeatDays":["mon","wed"],"important":true}]}
        """)
        guard case .todoAdd(let draft)? = out.first else { return XCTFail("expected todo.add") }
        XCTAssertEqual(draft.text, "call the notary", "trimmed")
        XCTAssertEqual(draft.note, "ask for the copy")
        XCTAssertEqual(draft.repeatDays, [2, 4], "mon=2, wed=4 in Calendar numbering")
        XCTAssertTrue(draft.important)
        XCTAssertEqual(draft.remindAt, Date(timeIntervalSince1970: 1_785_250_800))
    }

    func testTodoAddAcceptsALocalTimeWithoutAZone() {
        let out = parse(#"[{"do":"todo.add","text":"a","remindAt":"2026-07-28 15:00"}]"#)
        guard case .todoAdd(let draft)? = out.first else { return XCTFail("expected todo.add") }
        XCTAssertNotNil(draft.remindAt)
    }

    func testTodoAddWithoutTextIsSkipped() {
        XCTAssertEqual(parse(#"[{"do":"todo.add","note":"orphan"}]"#), [])
        XCTAssertEqual(parse(#"[{"do":"todo.add","text":"   "}]"#), [])
    }

    func testTodoCompleteNamesTheTask() {
        XCTAssertEqual(parse(#"[{"do":"todo.complete","text":"call the notary"}]"#),
                       [.todoComplete(text: "call the notary")])
    }

    // MARK: - The rest of the surface

    func testTrackerAndAwakeVerbs() {
        XCTAssertEqual(parse(#"[{"do":"tracker.start","task":"design"}]"#),
                       [.trackerStart(task: "design")])
        XCTAssertEqual(parse(#"[{"do":"tracker.stop"}]"#), [.trackerStop])
        XCTAssertEqual(parse(#"[{"do":"keepawake.on"}]"#), [.keepAwake(true)])
        XCTAssertEqual(parse(#"[{"do":"awake.off"}]"#), [.keepAwake(false)])
    }

    func testVerbsAreCaseAndSpaceInsensitive() {
        XCTAssertEqual(parse(#"[{"do":"  Timer.Pause "}]"#), [.timerPause])
    }

    // MARK: - hop:// links (what a Shortcut, and so Siri, can open)

    private func url(_ string: String) -> AgentCommand? {
        AgentCommandParser.parse(url: URL(string: string)!)
    }

    func testLinkStartsATimer() {
        XCTAssertEqual(url("hop://timer/start?minutes=16"), .timerStart(seconds: 960))
        XCTAssertEqual(url("hop://timer/start?duration=1h30m"), .timerStart(seconds: 5400))
    }

    func testLinkWithoutAPathStillWorks() {
        XCTAssertEqual(url("hop://timer?minutes=5"), .timerStart(seconds: 300))
    }

    func testLinkPausesResetsAndSwitchesModes() {
        XCTAssertEqual(url("hop://timer/pause"), .timerPause)
        XCTAssertEqual(url("hop://timer/reset"), .timerReset)
        XCTAssertEqual(url("hop://stopwatch/start"), .stopwatchStart)
        XCTAssertEqual(url("hop://awake/on"), .keepAwake(true))
    }

    func testLinkAddsATodoWithItsFields() {
        let out = url("hop://todo/add?text=call%20the%20notary&important=true&repeatDays=mon,wed")
        guard case .todoAdd(let draft)? = out else { return XCTFail("expected todo.add") }
        XCTAssertEqual(draft.text, "call the notary")
        XCTAssertTrue(draft.important, "a query carries booleans as text")
        XCTAssertEqual(draft.repeatDays, [2, 4], "a query cannot hold an array — mon,wed")
    }

    func testAForeignSchemeIsRefused() {
        XCTAssertNil(url("otherapp://timer/start?minutes=5"))
        XCTAssertNil(url("hop://nonsense/verb"))
    }
}
