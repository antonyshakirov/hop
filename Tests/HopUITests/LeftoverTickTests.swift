import XCTest
@testable import Hop

/// SPEC: docs/spec.md — "Leftovers, by name and by file".
final class LeftoverTickTests: XCTestCase {
    private func owner(ticked: Bool) -> UninstallController.CacheOwner {
        UninstallController.CacheOwner(identifier: "org.demo.app", name: "App", appPath: nil,
                                       paths: ["a", "b", "c"], bytes: 60, ticked: ticked,
                                       sizes: ["a": 10, "b": 20, "c": 30])
    }

    func testAFileTickedInAnUntickedProgramTakesOnlyThatFile() {
        var subject = owner(ticked: false)
        subject.toggle(path: "a")
        XCTAssertTrue(subject.ticked)
        XCTAssertEqual(subject.chosenPaths, ["a"])
        XCTAssertEqual(subject.chosenBytes, 10)
    }

    func testAFileUntickedInATickedProgramKeepsTheRest() {
        var subject = owner(ticked: true)
        subject.toggle(path: "b")
        XCTAssertTrue(subject.ticked)
        XCTAssertEqual(subject.chosenPaths, ["a", "c"])
        XCTAssertEqual(subject.chosenBytes, 40)
    }

    func testUntickingTheLastFileUnticksTheProgram() {
        var subject = owner(ticked: false)
        subject.toggle(path: "a")
        subject.toggle(path: "a")
        XCTAssertFalse(subject.ticked)
        XCTAssertTrue(subject.skipped.isEmpty)
    }
}
