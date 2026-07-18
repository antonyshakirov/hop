import XCTest
@testable import HopCore

final class TrackerEngineTests: XCTestCase {
    private var clock: Date!
    private var engine: TrackerEngine!
    private var changeCount = 0

    override func setUp() {
        super.setUp()
        clock = Date(timeIntervalSinceReferenceDate: 1_000_000)
        engine = TrackerEngine(now: { self.clock })
        engine.onChange = { [weak self] in self?.changeCount += 1 }
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    // MARK: - Structure

    func testAddProjectAppendsProjectAndReturnsItsID() {
        let id = engine.addProject(name: "Hop")
        XCTAssertEqual(engine.data.projects.map(\.id), [id])
        XCTAssertEqual(engine.data.projects.first?.name, "Hop")
    }

    func testAddTaskAppendsTaskUnderProject() {
        let projectID = engine.addProject(name: "Hop")
        let taskID = engine.addTask(projectID: projectID, name: "Ship 1.4")
        XCTAssertEqual(engine.data.tasks.map(\.id), [taskID])
        XCTAssertEqual(engine.data.tasks.first?.projectID, projectID)
    }

    func testRenameProjectUpdatesName() {
        let id = engine.addProject(name: "Old")
        engine.renameProject(id, to: "New")
        XCTAssertEqual(engine.data.projects.first?.name, "New")
    }

    func testRenameTaskUpdatesName() {
        let projectID = engine.addProject(name: "Hop")
        let taskID = engine.addTask(projectID: projectID, name: "Old")
        engine.renameTask(taskID, to: "New")
        XCTAssertEqual(engine.data.tasks.first?.name, "New")
    }

    func testSetExpandedTogglesProjectFlag() {
        let id = engine.addProject(name: "Hop")
        XCTAssertEqual(engine.data.projects.first?.isExpanded, true)
        engine.setExpanded(projectID: id, false)
        XCTAssertEqual(engine.data.projects.first?.isExpanded, false)
    }

    // MARK: - Tracking: start

    func testStartOpensIntervalWithNilEndAndReportsActiveTask() {
        let projectID = engine.addProject(name: "Hop")
        let taskID = engine.addTask(projectID: projectID, name: "Ship 1.4")

        engine.start(taskID: taskID)

        XCTAssertEqual(engine.activeTaskID, taskID)
        XCTAssertEqual(engine.data.intervals.count, 1)
        XCTAssertNil(engine.data.intervals.first?.end)
        XCTAssertEqual(engine.data.intervals.first?.start, clock)
    }

    func testStartingAnotherTaskClosesFirstIntervalAndOpensNew() {
        let projectID = engine.addProject(name: "Hop")
        let taskA = engine.addTask(projectID: projectID, name: "A")
        let taskB = engine.addTask(projectID: projectID, name: "B")

        engine.start(taskID: taskA)
        advance(60)
        engine.start(taskID: taskB)

        XCTAssertEqual(engine.activeTaskID, taskB)
        // exactly one open interval, ever
        let openIntervals = engine.data.intervals.filter { $0.end == nil }
        XCTAssertEqual(openIntervals.count, 1)
        XCTAssertEqual(openIntervals.first?.taskID, taskB)

        let closedInterval = engine.data.intervals.first { $0.taskID == taskA }
        XCTAssertEqual(closedInterval?.end, clock)
    }

    func testStartingAlreadyActiveTaskIsNoOp() {
        let projectID = engine.addProject(name: "Hop")
        let taskID = engine.addTask(projectID: projectID, name: "A")
        engine.start(taskID: taskID)

        changeCount = 0
        engine.start(taskID: taskID)

        XCTAssertEqual(engine.data.intervals.count, 1)
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Tracking: stopActive

    func testStopActiveClosesIntervalAndClearsActiveTask() {
        let projectID = engine.addProject(name: "Hop")
        let taskID = engine.addTask(projectID: projectID, name: "A")
        engine.start(taskID: taskID)
        advance(30)

        engine.stopActive()

        XCTAssertNil(engine.activeTaskID)
        XCTAssertEqual(engine.data.intervals.first?.end, clock)
    }

    func testStopActiveWhenIdleIsNoOp() {
        changeCount = 0

        engine.stopActive()

        XCTAssertNil(engine.activeTaskID)
        XCTAssertTrue(engine.data.intervals.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Deletion cascades

    func testDeletingActiveTaskStopsItAndDropsItsHistory() {
        // corrections aren't created by TrackerEngine yet (a later task), so
        // seed one directly to prove the cascade covers them too
        let projectID = UUID()
        let taskID = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: clock)],
            corrections: [TrackerCorrection(taskID: taskID, day: clock, seconds: -60)]
        ), now: { self.clock })

        engine.deleteTask(taskID)

        XCTAssertNil(engine.activeTaskID)
        XCTAssertTrue(engine.data.tasks.isEmpty)
        XCTAssertTrue(engine.data.intervals.isEmpty)
        XCTAssertTrue(engine.data.corrections.isEmpty)
    }

    func testDeletingProjectCascadesToItsTasksHistory() {
        let projectID = UUID()
        let taskA = UUID()
        let taskB = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [
                TrackerTask(id: taskA, projectID: projectID, name: "A"),
                TrackerTask(id: taskB, projectID: projectID, name: "B"),
            ],
            intervals: [
                TrackerInterval(taskID: taskA, start: clock, end: clock.addingTimeInterval(30)),
                TrackerInterval(taskID: taskB, start: clock.addingTimeInterval(30)),
            ],
            corrections: [TrackerCorrection(taskID: taskA, day: clock, seconds: -60)]
        ), now: { self.clock })

        engine.deleteProject(projectID)

        XCTAssertTrue(engine.data.projects.isEmpty)
        XCTAssertTrue(engine.data.tasks.isEmpty)
        XCTAssertTrue(engine.data.intervals.isEmpty)
        XCTAssertTrue(engine.data.corrections.isEmpty)
        XCTAssertNil(engine.activeTaskID)
    }

    // MARK: - onChange contract

    func testEveryMutatingCallFiresOnChangeExactlyOnce() {
        changeCount = 0
        let projectID = engine.addProject(name: "Hop")
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        let taskID = engine.addTask(projectID: projectID, name: "Ship")
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.renameProject(projectID, to: "Hop Renamed")
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.renameTask(taskID, to: "Ship Renamed")
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.setExpanded(projectID: projectID, false)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.start(taskID: taskID)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.stopActive()
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.deleteTask(taskID)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.deleteProject(projectID)
        XCTAssertEqual(changeCount, 1)
    }
}
