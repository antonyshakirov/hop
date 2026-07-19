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

    // MARK: - Manual edit: setToday

    func testSetTodayIncreasingValueAddsPositiveCorrectionAndGrowsTodayAndTotal() {
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: 10 * 60)]
        ), now: { self.clock }, calendar: calendar)
        engine.onChange = { [weak self] in self?.changeCount += 1 }

        changeCount = 0
        let result = engine.setToday(taskID: taskID, to: 25 * 60)

        XCTAssertTrue(result)
        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(engine.data.corrections.count, 2)
        XCTAssertEqual(engine.data.corrections.last?.seconds, 15 * 60)
        XCTAssertEqual(engine.data.corrections.last?.day, date(2026, 7, 17, 0, 0))
        XCTAssertEqual(engine.today(taskID: taskID), 25 * 60)
        XCTAssertEqual(engine.total(taskID: taskID), 25 * 60)
    }

    func testSetTodayBelowZeroClampsToZeroViaNegatedCurrentCorrection() {
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: 10 * 60)]
        ), now: { self.clock }, calendar: calendar)

        let result = engine.setToday(taskID: taskID, to: -5 * 60)

        XCTAssertTrue(result)
        XCTAssertEqual(engine.data.corrections.last?.seconds, -10 * 60)
        XCTAssertEqual(engine.today(taskID: taskID), 0)
    }

    func testSetTodayCalledTwiceSameDayAppendsTwoCorrectionsBothApply() {
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        engine.setToday(taskID: taskID, to: 10 * 60)
        engine.setToday(taskID: taskID, to: 20 * 60)

        XCTAssertEqual(engine.data.corrections.count, 2)
        XCTAssertEqual(engine.data.corrections.map(\.seconds), [10 * 60, 10 * 60])
        XCTAssertEqual(engine.today(taskID: taskID), 20 * 60)
    }

    func testSetTodayOnActiveTaskReturnsFalseAndMutatesNothing() {
        let projectID = engine.addProject(name: "Hop")
        let taskID = engine.addTask(projectID: projectID, name: "A")
        engine.start(taskID: taskID)

        changeCount = 0
        let result = engine.setToday(taskID: taskID, to: 25 * 60)

        XCTAssertFalse(result)
        XCTAssertTrue(engine.data.corrections.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    func testSetTodayReachesTargetEvenWhenRawTodaySumIsNegative() {
        // today() display-clamps at 0, but the delta must be computed against
        // the raw (unclamped) sum, or a heavily over-corrected task can never
        // be brought back up to a positive target in one edit.
        let projectID = UUID()
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: projectID, name: "Hop")],
            tasks: [TrackerTask(id: taskID, projectID: projectID, name: "A")],
            intervals: [],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: -10 * 3600)]
        ), now: { self.clock }, calendar: calendar)
        XCTAssertEqual(engine.today(taskID: taskID), 0) // raw sum is -10h, clamped for display

        let result = engine.setToday(taskID: taskID, to: 600)

        XCTAssertTrue(result)
        XCTAssertEqual(engine.today(taskID: taskID), 600)
    }

    func testSetTodayOnIdleTaskSucceedsWhileADifferentTaskIsActive() {
        let projectID = engine.addProject(name: "Hop")
        let taskA = engine.addTask(projectID: projectID, name: "A")
        let taskB = engine.addTask(projectID: projectID, name: "B")
        engine.start(taskID: taskA)

        let result = engine.setToday(taskID: taskB, to: 10 * 60)

        XCTAssertTrue(result)
        XCTAssertEqual(engine.data.corrections.count, 1)
        XCTAssertEqual(engine.data.corrections.first?.taskID, taskB)
        XCTAssertEqual(engine.today(taskID: taskB), 10 * 60)
    }

    // MARK: - rootOrder normalization

    func testNormalizeMissingRootOrderDerivesProjectsThenRootTasks() {
        let p1 = UUID(); let p2 = UUID()
        let nested = UUID(); let root = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: p1, name: "A"), TrackerProject(id: p2, name: "B")],
            tasks: [
                TrackerTask(id: nested, projectID: p1, name: "nested"),
                TrackerTask(id: root, projectID: nil, name: "root"),
            ],
            intervals: [], corrections: [], rootOrder: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.data.rootOrder, [p1, p2, root])
    }

    func testNormalizeDropsStaleIDsDedupesAndAppendsMissing() {
        let p1 = UUID(); let p2 = UUID(); let stale = UUID(); let root = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: p1, name: "A"), TrackerProject(id: p2, name: "B")],
            tasks: [TrackerTask(id: root, projectID: nil, name: "root")],
            intervals: [], corrections: [],
            rootOrder: [stale, p2, p2]  // stale id + duplicate + missing p1/root
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.data.rootOrder, [p2, p1, root])
    }

    // MARK: - Structure: rootOrder maintenance

    func testAddProjectAppendsToRootOrder() {
        let a = engine.addProject(name: "A")
        let b = engine.addProject(name: "B")
        XCTAssertEqual(engine.data.rootOrder, [a, b])
    }

    func testAddRootTaskAppendsToRootOrderWhileNestedTaskDoesNot() {
        let p = engine.addProject(name: "P")
        let nested = engine.addTask(projectID: p, name: "n")
        let root = engine.addTask(projectID: nil, name: "r")
        XCTAssertEqual(engine.data.rootOrder, [p, root])
        XCTAssertFalse(engine.data.rootOrder.contains(nested))
    }

    func testDeleteProjectRemovesItFromRootOrder() {
        let p = engine.addProject(name: "P")
        let root = engine.addTask(projectID: nil, name: "r")
        engine.deleteProject(p)
        XCTAssertEqual(engine.data.rootOrder, [root])
    }

    func testDeleteRootTaskRemovesItFromRootOrder() {
        let p = engine.addProject(name: "P")
        let root = engine.addTask(projectID: nil, name: "r")
        engine.deleteTask(root)
        XCTAssertEqual(engine.data.rootOrder, [p])
    }

    // MARK: - Reordering: move(taskID:toProjectID:at:)

    func testMoveTaskToProjectLiftsOutOfRoot() {
        let p = engine.addProject(name: "P")
        let root = engine.addTask(projectID: nil, name: "r")

        engine.move(taskID: root, toProjectID: p, at: 0)

        XCTAssertEqual(engine.data.tasks.first(where: { $0.id == root })?.projectID, p)
        XCTAssertEqual(engine.data.rootOrder, [p])
    }

    func testMoveTaskWithinProjectRespectsClampedPosition() {
        let p = engine.addProject(name: "P")
        let a = engine.addTask(projectID: p, name: "A")
        let b = engine.addTask(projectID: p, name: "B")
        let c = engine.addTask(projectID: p, name: "C")

        engine.move(taskID: c, toProjectID: p, at: 0)
        XCTAssertEqual(engine.data.tasks.filter { $0.projectID == p }.map(\.id), [c, a, b])

        engine.move(taskID: c, toProjectID: p, at: 99)   // past the end clamps to last
        XCTAssertEqual(engine.data.tasks.filter { $0.projectID == p }.map(\.id), [a, b, c])
    }

    func testMoveTaskBetweenProjects() {
        let p1 = engine.addProject(name: "P1")
        let p2 = engine.addProject(name: "P2")
        let a = engine.addTask(projectID: p1, name: "A")
        let b = engine.addTask(projectID: p2, name: "B")

        engine.move(taskID: a, toProjectID: p2, at: 0)

        XCTAssertEqual(engine.data.tasks.filter { $0.projectID == p2 }.map(\.id), [a, b])
        XCTAssertTrue(engine.data.tasks.filter { $0.projectID == p1 }.isEmpty)
    }

    func testMoveTaskToUnknownProjectIsNoOp() {
        let root = engine.addTask(projectID: nil, name: "r")
        changeCount = 0
        engine.move(taskID: root, toProjectID: UUID(), at: 0)
        XCTAssertNil(engine.data.tasks.first?.projectID)
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Reordering: move(taskID:toRootAt:)

    func testMoveTaskToRootAtClampedIndex() {
        let p = engine.addProject(name: "P")
        let root1 = engine.addTask(projectID: nil, name: "r1")   // rootOrder [p, root1]
        let nested = engine.addTask(projectID: p, name: "n")

        engine.move(taskID: nested, toRootAt: 1)

        XCTAssertNil(engine.data.tasks.first(where: { $0.id == nested })?.projectID)
        XCTAssertEqual(engine.data.rootOrder, [p, nested, root1])

        engine.move(taskID: root1, toRootAt: 0)   // reorder existing root task to front
        XCTAssertEqual(engine.data.rootOrder, [root1, p, nested])
    }

    // MARK: - Reordering: moveRootItem(from:to:)

    func testMoveRootItemReordersWithClamping() {
        let a = engine.addProject(name: "A")
        let b = engine.addProject(name: "B")
        let c = engine.addProject(name: "C")

        engine.moveRootItem(from: 0, to: 99)   // clamps to the end
        XCTAssertEqual(engine.data.rootOrder, [b, c, a])
    }

    func testMoveRootItemFromOutOfRangeIsNoOp() {
        let a = engine.addProject(name: "A")
        let b = engine.addProject(name: "B")
        changeCount = 0
        engine.moveRootItem(from: 99, to: 0)
        XCTAssertEqual(engine.data.rootOrder, [a, b])
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Root tasks behave like any task

    func testRootTaskTracksAndAggregatesLikeAnyTask() {
        let root = engine.addTask(projectID: nil, name: "r")
        engine.start(taskID: root)
        XCTAssertEqual(engine.activeTaskID, root)
        advance(60)
        engine.stopActive()
        XCTAssertEqual(engine.total(taskID: root), 60)
        XCTAssertEqual(engine.today(taskID: root), 60)
    }

    func testSetTodayWorksOnRootTask() {
        let root = engine.addTask(projectID: nil, name: "r")
        let ok = engine.setToday(taskID: root, to: 25 * 60)
        XCTAssertTrue(ok)
        XCTAssertEqual(engine.today(taskID: root), 25 * 60)
    }

    func testSingleActiveInvariantHoldsWithARootTask() {
        let p = engine.addProject(name: "P")
        let nested = engine.addTask(projectID: p, name: "n")
        let root = engine.addTask(projectID: nil, name: "r")

        engine.start(taskID: nested)
        advance(30)
        engine.start(taskID: root)

        XCTAssertEqual(engine.activeTaskID, root)
        XCTAssertEqual(engine.data.intervals.filter { $0.end == nil }.count, 1)
        XCTAssertNotNil(engine.data.intervals.first(where: { $0.taskID == nested })?.end)
    }

    func testRootTaskIsExcludedFromEveryProjectTotal() {
        let p = engine.addProject(name: "P")
        let root = engine.addTask(projectID: nil, name: "r")
        engine.start(taskID: root); advance(60); engine.stopActive()
        XCTAssertEqual(engine.total(projectID: p), 0)
        XCTAssertEqual(engine.today(projectID: p), 0)
    }

    // MARK: - onChange contract for the new methods

    func testNewMutatingCallsFireOnChangeExactlyOnce() {
        let p = engine.addProject(name: "P")
        let root = engine.addTask(projectID: nil, name: "r")
        let nested = engine.addTask(projectID: p, name: "n")

        changeCount = 0
        engine.move(taskID: nested, toRootAt: 0)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.move(taskID: nested, toProjectID: p, at: 0)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.moveRootItem(from: 0, to: 1)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        _ = engine.addTask(projectID: nil, name: "r2")
        XCTAssertEqual(changeCount, 1)

        _ = root   // silence unused warning; identity checked above via rootOrder
    }

    // MARK: - Migration reality check (Anton's live tracker.json shape)

    func testOldFileShapeLoadsLosslesslyAndDerivesRootOrder() throws {
        // Exactly the pre-8.5 shape: projects with nested tasks, an open
        // interval, corrections, expanded flags — and NO rootOrder field.
        let p1 = UUID(); let p2 = UUID()
        let t1 = UUID(); let t2 = UUID()
        clock = date(2026, 7, 17, 12, 0)
        let startTS = date(2026, 7, 17, 9, 0).timeIntervalSinceReferenceDate
        let dayTS = date(2026, 7, 17, 0, 0).timeIntervalSinceReferenceDate
        let json = """
        {
            "projects": [
                {"id": "\(p1.uuidString)", "name": "Hop", "isExpanded": true},
                {"id": "\(p2.uuidString)", "name": "Client", "isExpanded": false}
            ],
            "tasks": [
                {"id": "\(t1.uuidString)", "projectID": "\(p1.uuidString)", "name": "Ship"},
                {"id": "\(t2.uuidString)", "projectID": "\(p2.uuidString)", "name": "Invoice"}
            ],
            "intervals": [ {"taskID": "\(t1.uuidString)", "start": \(startTS)} ],
            "corrections": [ {"taskID": "\(t2.uuidString)", "day": \(dayTS), "seconds": 1800} ]
        }
        """
        let decoded = try JSONDecoder().decode(TrackerData.self, from: Data(json.utf8))
        engine = TrackerEngine(data: decoded, now: { self.clock }, calendar: calendar)

        // rootOrder derived to the projects in their existing order; no task lifted
        XCTAssertEqual(engine.data.rootOrder, [p1, p2])
        XCTAssertEqual(engine.data.tasks.first(where: { $0.id == t1 })?.projectID, p1)
        XCTAssertEqual(engine.data.tasks.first(where: { $0.id == t2 })?.projectID, p2)
        // open interval survives and still counts up
        XCTAssertEqual(engine.activeTaskID, t1)
        XCTAssertEqual(engine.today(taskID: t1), 3 * 3600)
        // corrections survive
        XCTAssertEqual(engine.today(taskID: t2), 30 * 60)
        // expanded flags survive
        XCTAssertEqual(engine.data.projects.first(where: { $0.id == p1 })?.isExpanded, true)
        XCTAssertEqual(engine.data.projects.first(where: { $0.id == p2 })?.isExpanded, false)
    }
}
