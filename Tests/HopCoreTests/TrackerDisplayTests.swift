import XCTest
@testable import HopCore

/// The tracker has no completed pile, so importance is its only display group —
/// and, like the to-do list, it is display-only: marking a task never mutates
/// the stored order, so unmarking returns it to its own slot.
final class TrackerDisplayTests: XCTestCase {

    private var idMap: [String: UUID] = [:]
    private func id(_ name: String) -> UUID {
        if let existing = idMap[name] { return existing }
        let fresh = UUID()
        idMap[name] = fresh
        return fresh
    }

    // name, important
    private func make(_ spec: [(String, Bool)]) -> [TrackerTask] {
        spec.map { TrackerTask(id: id($0.0), name: $0.0, important: $0.1) }
    }
    private func names(_ tasks: [TrackerTask]) -> [String] { tasks.map(\.name) }

    func testImportantFirstIsStableWithinEachGroup() {
        let tasks = make([("a", false), ("b", true), ("c", false), ("d", true)])
        XCTAssertEqual(names(TrackerDisplay.order(tasks, importantFirst: true)),
                       ["b", "d", "a", "c"])
    }

    func testOrderIsUntouchedWhenTheSettingIsOff() {
        let tasks = make([("a", false), ("b", true)])
        XCTAssertEqual(names(TrackerDisplay.order(tasks, importantFirst: false)), ["a", "b"])
    }

    func testUnmarkingReturnsTheTaskToItsStoredSlot() {
        var tasks = make([("a", false), ("b", true), ("c", false)])
        XCTAssertEqual(names(TrackerDisplay.order(tasks, importantFirst: true)), ["b", "a", "c"])
        tasks[1].important = false
        XCTAssertEqual(names(TrackerDisplay.order(tasks, importantFirst: true)), ["a", "b", "c"])
    }

    func testDragIsClampedInsideTheImportantGroup() {
        let tasks = make([("b", true), ("d", true), ("a", false)])
        let clamped = TrackerDisplay.clampedInsertion(tasks, dragging: id("b"),
                                                      rawInsertion: 2, importantFirst: true)
        XCTAssertEqual(clamped, 1)
    }

    func testDragIsUnrestrictedWhenTheSettingIsOff() {
        let tasks = make([("b", true), ("d", true), ("a", false)])
        let clamped = TrackerDisplay.clampedInsertion(tasks, dragging: id("b"),
                                                      rawInsertion: 2, importantFirst: false)
        XCTAssertEqual(clamped, 2, "with no groups there is nothing to clamp against")
    }

    // MARK: - The top level, where projects sit among the tasks

    private func project(_ name: String) -> TrackerItem {
        .project(TrackerProject(id: id(name), name: name))
    }

    private func task(_ name: String, important: Bool) -> TrackerItem {
        .task(TrackerTask(id: id(name), name: name, important: important))
    }

    private func names(_ items: [TrackerItem]) -> [String] {
        items.map {
            switch $0 {
            case .project(let p): return p.name
            case .task(let t): return t.name
            }
        }
    }

    func testAStarredTaskFloatsPastOtherTasksAndNotPastProjects() {
        let items = [task("a", important: false), project("P"), task("b", important: true)]
        // "b" takes the first TASK slot; the project stays exactly where it was
        XCTAssertEqual(names(TrackerDisplay.order(topLevel: items, importantFirst: true)),
                       ["b", "P", "a"])
    }

    func testWithTheSettingOffTheTopLevelIsUntouched() {
        let items = [task("a", important: false), project("P"), task("b", important: true)]
        XCTAssertEqual(names(TrackerDisplay.order(topLevel: items, importantFirst: false)),
                       ["a", "P", "b"])
    }

    func testATopLevelOfProjectsAloneIsLeftAlone() {
        let items = [project("A"), project("B")]
        XCTAssertEqual(names(TrackerDisplay.order(topLevel: items, importantFirst: true)),
                       ["A", "B"])
    }
}
