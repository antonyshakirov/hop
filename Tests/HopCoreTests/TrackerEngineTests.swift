import XCTest
@testable import HopCore

final class TrackerEngineTests: XCTestCase {
    private var clock: Date!
    private var engine: TrackerEngine!
    private var changeCount = 0
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        clock = Date(timeIntervalSinceReferenceDate: 1_000_000)
        engine = TrackerEngine(now: { self.clock }, calendar: calendar)
        engine.onChange = { [weak self] in self?.changeCount += 1 }
    }

    private func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    /// Builds an unambiguous date via the fixed UTC test calendar so midnight
    /// boundaries in aggregate tests never depend on the host's time zone.
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
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

    // MARK: - Aggregates: total / today

    func testTotalSumsClosedIntervals() {
        let projectID = UUID()
        let taskID = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [
                TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 10, 0), end: date(2026, 7, 17, 10, 30)),
                TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 11, 0), end: date(2026, 7, 17, 12, 0)),
            ],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(taskID: taskID), 90 * 60)
    }

    func testOpenIntervalCountsUpAsClockAdvances() {
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 9, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 9, 0))],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(taskID: taskID), 0)
        advance(30 * 60)
        XCTAssertEqual(engine.total(taskID: taskID), 30 * 60)
        XCTAssertEqual(engine.today(taskID: taskID), 30 * 60)
    }

    func testIntervalCrossingMidnightSplitsBetweenTodayAndTotalAtQueryTime() {
        let projectID = UUID()
        let taskID = UUID()
        // 22:00 yesterday -> 01:00 today: 1h should land in today, 3h in total.
        clock = date(2026, 7, 17, 1, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 16, 22, 0), end: date(2026, 7, 17, 1, 0))],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.today(taskID: taskID), 1 * 3600)
        XCTAssertEqual(engine.total(taskID: taskID), 3 * 3600)
    }

    func testTaskStartedYesterdayStillRunningShowsOnlyPostMidnightPartInToday() {
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 2, 30)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 16, 20, 0))], // still open
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.today(taskID: taskID), 2.5 * 3600)
        XCTAssertEqual(engine.total(taskID: taskID), 6.5 * 3600)
    }

    func testProjectTotalsSumChildTasks() {
        let projectID = UUID()
        let taskA = UUID()
        let taskB = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [
                TrackerTask(id: taskA, projectID: projectID, name: "A"),
                TrackerTask(id: taskB, projectID: projectID, name: "B"),
            ],
            intervals: [
                TrackerInterval(taskID: taskA, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0)),
                TrackerInterval(taskID: taskB, start: date(2026, 7, 17, 10, 0), end: date(2026, 7, 17, 11, 30)),
            ],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(projectID: projectID), 2.5 * 3600)
        XCTAssertEqual(engine.today(projectID: projectID), 2.5 * 3600)
    }

    func testCorrectionsScopeTotalIncludesAllDaysTodayIncludesOnlyToday() {
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [],
            corrections: [
                TrackerCorrection(taskID: taskID, day: date(2026, 7, 16, 0, 0), seconds: 20 * 60), // yesterday
                TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: 15 * 60), // today
            ]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.today(taskID: taskID), 15 * 60)
        XCTAssertEqual(engine.total(taskID: taskID), 35 * 60)
    }

    func testTotalAndTodayNeverGoNegativeDespiteLargeNegativeCorrection() {
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0))],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: -10 * 3600)]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(taskID: taskID), 0)
        XCTAssertEqual(engine.today(taskID: taskID), 0)
    }

    func testProjectTotalSumsAlreadyClampedTaskValuesRatherThanClampingTheRawSum() {
        let projectID = UUID()
        let taskA = UUID()
        let taskB = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [
                TrackerTask(id: taskA, projectID: projectID, name: "A"),
                TrackerTask(id: taskB, projectID: projectID, name: "B"),
            ],
            intervals: [
                TrackerInterval(taskID: taskB, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0)),
            ],
            corrections: [
                // if the raw sum were clamped only at the project level, -10h + 1h
                // would clamp to 0; clamping per task first keeps task B's 1h intact.
                TrackerCorrection(taskID: taskA, day: date(2026, 7, 17, 0, 0), seconds: -10 * 3600),
            ]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(projectID: projectID), 1 * 3600)
    }
}
