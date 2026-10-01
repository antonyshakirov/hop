import XCTest
@testable import HopCore

final class AwakeResumeTests: XCTestCase {
    private let saved = Date(timeIntervalSince1970: 1_000_000)

    private func resume(active: Bool = true, until: Date? = nil, lid: Bool = false) -> AwakeResume {
        AwakeResume(active: active, until: until, optionSeconds: until == nil ? nil : 4 * 3600,
                    lid: lid, savedAt: saved)
    }

    func testEndlessSessionComesBackAfterTheRelaunch() {
        XCTAssertEqual(resume().session(now: saved.addingTimeInterval(5)), .endless)
    }

    func testTimedSessionKeepsItsOwnEnd() {
        let end = saved.addingTimeInterval(3 * 3600)
        XCTAssertEqual(resume(until: end).session(now: saved.addingTimeInterval(5)), .until(end))
    }

    func testSessionThatRanOutDuringTheRelaunchStaysOff() {
        let end = saved.addingTimeInterval(3)
        XCTAssertEqual(resume(until: end).session(now: saved.addingTimeInterval(5)), AwakeResume.Session.none)
    }

    func testNothingComesBackWhenKeepAwakeWasOff() {
        XCTAssertEqual(resume(active: false, lid: true).session(now: saved.addingTimeInterval(5)),
                       AwakeResume.Session.none)
    }

    func testRecordOlderThanTheRelaunchWindowIsIgnored() {
        let late = saved.addingTimeInterval(AwakeResume.relaunchWindow + 1)
        XCTAssertEqual(resume().session(now: late), AwakeResume.Session.none)
        XCTAssertFalse(resume(lid: true).keepsLid(now: late))
    }

    func testRecordFromTheFutureIsIgnored() {
        XCTAssertEqual(resume().session(now: saved.addingTimeInterval(-60)), AwakeResume.Session.none)
    }

    func testLidModeComesBackOnItsOwn() {
        XCTAssertTrue(resume(active: false, lid: true).keepsLid(now: saved.addingTimeInterval(5)))
        XCTAssertFalse(resume(active: true, lid: false).keepsLid(now: saved.addingTimeInterval(5)))
    }

    func testRecordSurvivesStorage() throws {
        let original = resume(until: saved.addingTimeInterval(900), lid: true)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AwakeResume.self, from: data), original)
    }
}
