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

    // MARK: - Structure (flat: every task is a root task)

    func testAddTaskAppendsRootTaskAndReturnsItsID() {
        let id = engine.addTask(name: "Ship 1.4")
        XCTAssertEqual(engine.data.tasks.map(\.id), [id])
        XCTAssertNil(engine.data.tasks.first?.projectID)
        XCTAssertEqual(engine.data.tasks.first?.name, "Ship 1.4")
        XCTAssertEqual(engine.data.rootOrder, [id])
    }

    func testAddTaskAppendsToRootOrderInInsertionOrder() {
        let a = engine.addTask(name: "A")
        let b = engine.addTask(name: "B")
        XCTAssertEqual(engine.data.rootOrder, [a, b])
    }

    func testRenameTaskUpdatesName() {
        let taskID = engine.addTask(name: "Old")
        engine.renameTask(taskID, to: "New")
        XCTAssertEqual(engine.data.tasks.first?.name, "New")
    }

    func testDeleteTaskRemovesItFromRootOrder() {
        let a = engine.addTask(name: "A")
        let b = engine.addTask(name: "B")
        engine.deleteTask(a)
        XCTAssertEqual(engine.data.rootOrder, [b])
    }

    // MARK: - Tracking: start

    func testStartOpensIntervalWithNilEndAndReportsActiveTask() {
        let taskID = engine.addTask(name: "Ship 1.4")

        engine.start(taskID: taskID)

        XCTAssertEqual(engine.activeTaskID, taskID)
        XCTAssertEqual(engine.data.intervals.count, 1)
        XCTAssertNil(engine.data.intervals.first?.end)
        XCTAssertEqual(engine.data.intervals.first?.start, clock)
    }

    func testStartingAnotherTaskClosesFirstIntervalAndOpensNew() {
        let taskA = engine.addTask(name: "A")
        let taskB = engine.addTask(name: "B")

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
        let taskID = engine.addTask(name: "A")
        engine.start(taskID: taskID)

        changeCount = 0
        engine.start(taskID: taskID)

        XCTAssertEqual(engine.data.intervals.count, 1)
        XCTAssertEqual(changeCount, 0)
    }

    /// An unknown id must not open an orphan interval or claim active state.
    func testStartWithUnknownIDIsNoOp() {
        _ = engine.addTask(name: "A")
        changeCount = 0

        engine.start(taskID: UUID())

        XCTAssertNil(engine.activeTaskID)
        XCTAssertTrue(engine.data.intervals.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    func testDeleteTaskWithUnknownIDIsNoOp() {
        _ = engine.addTask(name: "A")
        changeCount = 0

        engine.deleteTask(UUID())

        XCTAssertEqual(engine.data.rootOrder.count, 1)
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Tracking: stopActive

    func testStopActiveClosesIntervalAndClearsActiveTask() {
        let taskID = engine.addTask(name: "A")
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

    /// The open interval start is exposed so the view can flag a run over 8h.
    func testActiveIntervalStartReturnsOpenStartWhenActiveElseNil() {
        let taskID = engine.addTask(name: "A")
        XCTAssertNil(engine.activeIntervalStart)

        engine.start(taskID: taskID)
        XCTAssertEqual(engine.activeIntervalStart, clock)

        engine.stopActive()
        XCTAssertNil(engine.activeIntervalStart)
    }

    // MARK: - Deletion cascade

    func testDeletingActiveTaskStopsItAndDropsItsHistory() {
        let taskID = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: clock)],
            corrections: [TrackerCorrection(taskID: taskID, day: clock, seconds: -60)]
        ), now: { self.clock })

        engine.deleteTask(taskID)

        XCTAssertNil(engine.activeTaskID)
        XCTAssertTrue(engine.data.tasks.isEmpty)
        XCTAssertTrue(engine.data.intervals.isEmpty)
        XCTAssertTrue(engine.data.corrections.isEmpty)
    }

    // MARK: - onChange contract

    func testEveryMutatingCallFiresOnChangeExactlyOnce() {
        changeCount = 0
        let taskID = engine.addTask(name: "Ship")
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.renameTask(taskID, to: "Ship Renamed")
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.start(taskID: taskID)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.stopActive()
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.setToday(taskID: taskID, to: 5 * 60)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.setTotal(taskID: taskID, to: 10 * 60)
        XCTAssertEqual(changeCount, 1)

        changeCount = 0
        engine.deleteTask(taskID)
        XCTAssertEqual(changeCount, 1)
    }

    func testMoveRootItemFiresOnChangeExactlyOnce() {
        _ = engine.addTask(name: "A")
        _ = engine.addTask(name: "B")
        changeCount = 0
        engine.moveRootItem(from: 0, to: 1)
        XCTAssertEqual(changeCount, 1)
    }

    // MARK: - Aggregates: total / today

    func testTotalSumsClosedIntervals() {
        let taskID = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [
                TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 10, 0), end: date(2026, 7, 17, 10, 30)),
                TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 11, 0), end: date(2026, 7, 17, 12, 0)),
            ],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(taskID: taskID), 90 * 60)
    }

    func testOpenIntervalCountsUpAsClockAdvances() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 9, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 9, 0))],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(taskID: taskID), 0)
        advance(30 * 60)
        XCTAssertEqual(engine.total(taskID: taskID), 30 * 60)
        XCTAssertEqual(engine.today(taskID: taskID), 30 * 60)
    }

    func testIntervalCrossingMidnightSplitsBetweenTodayAndTotalAtQueryTime() {
        let taskID = UUID()
        // 22:00 yesterday -> 01:00 today: 1h should land in today, 3h in total.
        clock = date(2026, 7, 17, 1, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 16, 22, 0), end: date(2026, 7, 17, 1, 0))],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.today(taskID: taskID), 1 * 3600)
        XCTAssertEqual(engine.total(taskID: taskID), 3 * 3600)
    }

    func testTaskStartedYesterdayStillRunningShowsOnlyPostMidnightPartInToday() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 2, 30)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 16, 20, 0))], // still open
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.today(taskID: taskID), 2.5 * 3600)
        XCTAssertEqual(engine.total(taskID: taskID), 6.5 * 3600)
    }

    func testCorrectionsScopeTotalIncludesAllDaysTodayIncludesOnlyToday() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
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
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0))],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: -10 * 3600)]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.total(taskID: taskID), 0)
        XCTAssertEqual(engine.today(taskID: taskID), 0)
    }

    // MARK: - Manual edit: setToday (kept for the menu-bar path)

    func testSetTodayIncreasingValueAddsPositiveCorrectionAndGrowsTodayAndTotal() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
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

    func testSetTodayReachesTargetEvenWhenRawTodaySumIsNegative() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: -10 * 3600)]
        ), now: { self.clock }, calendar: calendar)
        XCTAssertEqual(engine.today(taskID: taskID), 0) // raw sum is -10h, clamped for display

        let result = engine.setToday(taskID: taskID, to: 600)

        XCTAssertTrue(result)
        XCTAssertEqual(engine.today(taskID: taskID), 600)
    }

    /// An unknown id adds no orphan correction and reports failure.
    func testSetTodayWithUnknownIDIsNoOpAndAddsNoCorrection() {
        _ = engine.addTask(name: "A")
        changeCount = 0

        let result = engine.setToday(taskID: UUID(), to: 25 * 60)

        XCTAssertFalse(result)
        XCTAssertTrue(engine.data.corrections.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    /// Re-setting today to the value it already holds writes no (zero-delta)
    /// correction and fires no redundant save.
    func testSetTodayToCurrentValueWritesNoCorrection() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 17, 0, 0), seconds: 10 * 60)]
        ), now: { self.clock }, calendar: calendar)
        engine.onChange = { [weak self] in self?.changeCount += 1 }
        let before = engine.data.corrections.count
        changeCount = 0

        let result = engine.setToday(taskID: taskID, to: 10 * 60)   // already 10 min

        XCTAssertTrue(result)
        XCTAssertEqual(engine.data.corrections.count, before)
        XCTAssertEqual(changeCount, 0)
    }

    func testSetTodayOnActiveTaskReturnsFalseAndMutatesNothing() {
        let taskID = engine.addTask(name: "A")
        engine.start(taskID: taskID)

        changeCount = 0
        let result = engine.setToday(taskID: taskID, to: 25 * 60)

        XCTAssertFalse(result)
        XCTAssertTrue(engine.data.corrections.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Manual edit: setTotal (edit the all-time total)

    func testSetTotalIncreasingValueAddsCorrectionDatedTodayAndGrowsTotal() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            // 1h logged on a PAST day: total counts it, today does not.
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 10, 9, 0), end: date(2026, 7, 10, 10, 0))],
            corrections: []
        ), now: { self.clock }, calendar: calendar)
        engine.onChange = { [weak self] in self?.changeCount += 1 }

        changeCount = 0
        let result = engine.setTotal(taskID: taskID, to: 2 * 3600)

        XCTAssertTrue(result)
        XCTAssertEqual(changeCount, 1)
        // delta = target(2h) - rawTotal(1h) = 1h, dated the start of TODAY
        XCTAssertEqual(engine.data.corrections.count, 1)
        XCTAssertEqual(engine.data.corrections.last?.seconds, 1 * 3600)
        XCTAssertEqual(engine.data.corrections.last?.day, date(2026, 7, 17, 0, 0))
        XCTAssertEqual(engine.total(taskID: taskID), 2 * 3600)
    }

    func testSetTotalBelowZeroClampsTotalToZero() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0))],
            corrections: []
        ), now: { self.clock }, calendar: calendar)

        let result = engine.setTotal(taskID: taskID, to: -5 * 60)

        XCTAssertTrue(result)
        // target clamps to 0; delta = 0 - rawTotal(1h) = -1h
        XCTAssertEqual(engine.data.corrections.last?.seconds, -1 * 3600)
        XCTAssertEqual(engine.total(taskID: taskID), 0)
    }

    func testSetTotalReachesTargetEvenWhenRawTotalSumIsNegative() {
        // total() display-clamps at 0, but the delta must diff against the RAW
        // (unclamped) total — the same lesson setToday learned against rawToday.
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [],
            corrections: [TrackerCorrection(taskID: taskID, day: date(2026, 7, 16, 0, 0), seconds: -10 * 3600)]
        ), now: { self.clock }, calendar: calendar)
        XCTAssertEqual(engine.total(taskID: taskID), 0) // raw total is -10h, clamped for display

        let result = engine.setTotal(taskID: taskID, to: 600)

        XCTAssertTrue(result)
        // delta = 600 - (-36000) = 36600, so the raw total reaches exactly 600
        XCTAssertEqual(engine.data.corrections.last?.seconds, 36600)
        XCTAssertEqual(engine.total(taskID: taskID), 600)
    }

    /// An unknown id adds no orphan correction and reports failure.
    func testSetTotalWithUnknownIDIsNoOpAndAddsNoCorrection() {
        _ = engine.addTask(name: "A")
        changeCount = 0

        let result = engine.setTotal(taskID: UUID(), to: 25 * 60)

        XCTAssertFalse(result)
        XCTAssertTrue(engine.data.corrections.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    /// Re-setting the total to the value it already holds writes no (zero-delta)
    /// correction and fires no redundant save — also closes drag-left-at-zero.
    func testSetTotalToCurrentValueWritesNoCorrection() {
        let taskID = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: taskID, name: "A")],
            intervals: [TrackerInterval(taskID: taskID, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0))],
            corrections: []
        ), now: { self.clock }, calendar: calendar)
        engine.onChange = { [weak self] in self?.changeCount += 1 }
        changeCount = 0

        let result = engine.setTotal(taskID: taskID, to: 1 * 3600)   // already exactly 1h

        XCTAssertTrue(result)
        XCTAssertTrue(engine.data.corrections.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    func testSetTotalOnActiveTaskReturnsFalseAndMutatesNothing() {
        let taskID = engine.addTask(name: "A")
        engine.start(taskID: taskID)

        changeCount = 0
        let result = engine.setTotal(taskID: taskID, to: 25 * 60)

        XCTAssertFalse(result)
        XCTAssertTrue(engine.data.corrections.isEmpty)
        XCTAssertEqual(changeCount, 0)
    }

    func testSetTotalOnIdleTaskSucceedsWhileADifferentTaskIsActive() {
        let taskA = engine.addTask(name: "A")
        let taskB = engine.addTask(name: "B")
        engine.start(taskID: taskA)

        let result = engine.setTotal(taskID: taskB, to: 10 * 60)

        XCTAssertTrue(result)
        XCTAssertEqual(engine.data.corrections.count, 1)
        XCTAssertEqual(engine.data.corrections.first?.taskID, taskB)
        XCTAssertEqual(engine.total(taskID: taskB), 10 * 60)
    }

    // MARK: - Loading a file that has projects

    /// The fixture that matters: 2 projects + top-level tasks + an ACTIVE task
    /// inside a project. Everything keeps its place, the orders are derived
    /// where absent, and intervals/corrections/the open interval all survive.
    func testAFileWithProjectsLoadsAsItWasWritten() {
        let p1 = UUID(); let p2 = UUID()
        let t1a = UUID(); let t1b = UUID()   // inside p1
        let t2a = UUID()                     // inside p2, ACTIVE
        let r1 = UUID(); let r2 = UUID()     // top-level tasks
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [
                TrackerProject(id: p1, name: "Hop", isExpanded: true),
                TrackerProject(id: p2, name: "Client", isExpanded: false),
            ],
            tasks: [
                TrackerTask(id: t1a, projectID: p1, name: "t1a"),
                TrackerTask(id: t1b, projectID: p1, name: "t1b"),
                TrackerTask(id: t2a, projectID: p2, name: "t2a"),
                TrackerTask(id: r1, projectID: nil, name: "r1"),
                TrackerTask(id: r2, projectID: nil, name: "r2"),
            ],
            intervals: [
                TrackerInterval(taskID: t1a, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0)),
                TrackerInterval(taskID: t2a, start: date(2026, 7, 17, 11, 0)), // open / ACTIVE
            ],
            corrections: [
                TrackerCorrection(taskID: t1b, day: date(2026, 7, 17, 0, 0), seconds: 30 * 60),
                TrackerCorrection(taskID: r1, day: date(2026, 7, 17, 0, 0), seconds: 5 * 60),
            ],
            rootOrder: [p1, r1, p2, r2]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.data.projects.count, 2)
        XCTAssertEqual(engine.data.rootOrder, [p1, r1, p2, r2])
        XCTAssertEqual(engine.tasks(in: p1).map(\.id), [t1a, t1b])
        XCTAssertEqual(engine.tasks(in: p2).map(\.id), [t2a])
        // the active task inside a project is still active
        XCTAssertEqual(engine.activeTaskID, t2a)
        XCTAssertEqual(engine.activeIntervalStart, date(2026, 7, 17, 11, 0))
        XCTAssertTrue(engine.isTracking(projectID: p2))
        XCTAssertFalse(engine.isTracking(projectID: p1))
        // all history survives
        XCTAssertEqual(engine.total(taskID: t1a), 1 * 3600)
        XCTAssertEqual(engine.total(taskID: t1b), 30 * 60)
        XCTAssertEqual(engine.total(taskID: t2a), 1 * 3600)   // open interval 11:00 -> 12:00
        XCTAssertEqual(engine.total(taskID: r1), 5 * 60)
        // and the project's own figure is its tasks added up
        XCTAssertEqual(engine.amount(projectID: p1, period: .total), 1 * 3600 + 30 * 60)
    }

    func testATaskPointingAtAMissingProjectComesBackToTheTopLevel() {
        let ghost = UUID(); let orphan = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: orphan, projectID: ghost, name: "orphan")],
            intervals: [], corrections: [], rootOrder: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertNil(engine.data.tasks.first?.projectID)
        XCTAssertEqual(engine.data.rootOrder, [orphan])
    }

    func testTheTopLevelReadsAsProjectsAndLooseTasksMixed() {
        let p = UUID(); let loose = UUID(); let inside = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: p, name: "P")],
            tasks: [
                TrackerTask(id: inside, projectID: p, name: "inside"),
                TrackerTask(id: loose, projectID: nil, name: "loose"),
            ],
            intervals: [], corrections: [], rootOrder: [loose, p]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.topLevel.map(\.id), [loose, p])
        guard case .task = engine.topLevel.first else { return XCTFail("expected a task first") }
        guard case .project = engine.topLevel.last else { return XCTFail("expected a project last") }
    }

    /// A file written before the orders existed carries neither: they are
    /// derived from the arrays — projects first, then the loose tasks.
    func testAFileWithNoOrdersDerivesThemFromTheArrays() {
        let p1 = UUID(); let p2 = UUID()
        let t1 = UUID(); let t2 = UUID(); let root = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: p1, name: "A"), TrackerProject(id: p2, name: "B")],
            tasks: [
                TrackerTask(id: t1, projectID: p1, name: "t1"),
                TrackerTask(id: t2, projectID: p2, name: "t2"),
                TrackerTask(id: root, projectID: nil, name: "root"),
            ],
            intervals: [], corrections: [], rootOrder: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.data.rootOrder, [p1, p2, root])
        XCTAssertEqual(engine.tasks(in: p1).map(\.id), [t1])
        XCTAssertEqual(engine.tasks(in: p2).map(\.id), [t2])
    }

    /// The years without projects wrote a list of tasks and nothing else. It
    /// loads as exactly that, in the order it was left in.
    func testAFileFromTheFlatYearsLoadsUntouched() {
        let a = UUID(); let b = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: a, name: "A"), TrackerTask(id: b, name: "B")],
            intervals: [], corrections: [], rootOrder: [b, a]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertTrue(engine.data.projects.isEmpty)
        XCTAssertEqual(engine.data.rootOrder, [b, a])
        XCTAssertTrue(engine.data.tasks.allSatisfy { $0.projectID == nil })
    }

    /// A 1.3.x tracker.json on disk — nested tasks, an open interval,
    /// corrections, expanded flags, and none of the order keys — loads whole.
    func testAFileFromBeforeTheFlatYearsLoadsLosslessly() throws {
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

        // both projects are there, each holding its own task, and the folded
        // one is still folded
        XCTAssertEqual(engine.data.rootOrder, [p1, p2])
        XCTAssertEqual(engine.tasks(in: p1).map(\.id), [t1])
        XCTAssertEqual(engine.tasks(in: p2).map(\.id), [t2])
        XCTAssertEqual(engine.data.projects.last?.isExpanded, false)
        // open interval survives and still counts up
        XCTAssertEqual(engine.activeTaskID, t1)
        XCTAssertEqual(engine.today(taskID: t1), 3 * 3600)
        // corrections survive
        XCTAssertEqual(engine.today(taskID: t2), 30 * 60)
    }

    // MARK: - rootOrder normalization (flat)

    func testNormalizeMissingRootOrderDerivesTaskOrder() {
        let a = UUID(); let b = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: a, name: "A"), TrackerTask(id: b, name: "B")],
            intervals: [], corrections: [], rootOrder: []
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.data.rootOrder, [a, b])
    }

    func testNormalizeDropsStaleIDsDedupesAndAppendsMissing() {
        let a = UUID(); let b = UUID(); let stale = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: a, name: "A"), TrackerTask(id: b, name: "B")],
            intervals: [], corrections: [],
            rootOrder: [stale, b, b]   // stale id + duplicate + missing a
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.data.rootOrder, [b, a])
    }

    // MARK: - Reordering: moveRootItem(from:to:) (the flat-list drag)

    func testMoveRootItemReordersWithClamping() {
        let a = engine.addTask(name: "A")
        let b = engine.addTask(name: "B")
        let c = engine.addTask(name: "C")

        engine.moveRootItem(from: 0, to: 99)   // clamps to the end
        XCTAssertEqual(engine.data.rootOrder, [b, c, a])
    }

    func testMoveRootItemFromOutOfRangeIsNoOp() {
        let a = engine.addTask(name: "A")
        let b = engine.addTask(name: "B")
        changeCount = 0
        engine.moveRootItem(from: 99, to: 0)
        XCTAssertEqual(engine.data.rootOrder, [a, b])
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - A task tracks and aggregates end to end

    func testTaskTracksAndAggregates() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        XCTAssertEqual(engine.activeTaskID, task)
        advance(60)
        engine.stopActive()
        XCTAssertEqual(engine.total(taskID: task), 60)
        XCTAssertEqual(engine.today(taskID: task), 60)
    }

    // MARK: - Projects

    func testAProjectIsAddedToTheTopLevel() {
        let task = engine.addTask(name: "loose")
        changeCount = 0
        let project = engine.addProject(name: "Hop")

        XCTAssertEqual(engine.data.rootOrder, [task, project])
        XCTAssertTrue(engine.tasks(in: project).isEmpty)
        XCTAssertEqual(changeCount, 1)
    }

    func testATaskCanBeAddedStraightIntoAProject() {
        let project = engine.addProject(name: "Hop")
        let task = engine.addTask(name: "ship", projectID: project)

        XCTAssertEqual(engine.tasks(in: project).map(\.id), [task])
        XCTAssertFalse(engine.data.rootOrder.contains(task))
        XCTAssertEqual(engine.data.tasks.first?.projectID, project)
    }

    func testAnUnknownProjectLeavesTheTaskAtTheTopLevel() {
        let task = engine.addTask(name: "ship", projectID: UUID())

        XCTAssertEqual(engine.data.rootOrder, [task])
        XCTAssertNil(engine.data.tasks.first?.projectID)
    }

    func testRenamingAndFoldingAProjectStick() {
        let project = engine.addProject(name: "Hop")
        engine.renameProject(project, to: "Hop 1.9")
        engine.setProjectExpanded(project, false)

        XCTAssertEqual(engine.data.projects.first?.name, "Hop 1.9")
        XCTAssertEqual(engine.data.projects.first?.isExpanded, false)
    }

    func testAZeroDeltaProjectEditSavesNothing() {
        let project = engine.addProject(name: "Hop")
        changeCount = 0
        engine.renameProject(project, to: "Hop")
        engine.setProjectExpanded(project, true)
        engine.renameProject(UUID(), to: "ghost")
        XCTAssertEqual(changeCount, 0)
    }

    func testDeletingAProjectTakesItsTasksAndTheirHistory() {
        let project = engine.addProject(name: "Hop")
        let inside = engine.addTask(name: "ship", projectID: project)
        let loose = engine.addTask(name: "loose")
        engine.start(taskID: inside)
        advance(600)
        engine.stopActive()
        engine.setTotal(taskID: loose, to: 300)

        engine.deleteProject(project)

        XCTAssertTrue(engine.data.projects.isEmpty)
        XCTAssertEqual(engine.data.tasks.map(\.id), [loose])
        XCTAssertEqual(engine.data.rootOrder, [loose])
        XCTAssertTrue(engine.data.intervals.isEmpty)
        // the loose task's own correction is untouched
        XCTAssertEqual(engine.total(taskID: loose), 300)
    }

    func testDeletingTheProjectOfTheRunningTaskStopsTheClock() {
        let project = engine.addProject(name: "Hop")
        let inside = engine.addTask(name: "ship", projectID: project)
        engine.start(taskID: inside)

        engine.deleteProject(project)

        XCTAssertNil(engine.activeTaskID)
    }

    func testDeletingAnUnknownProjectSavesNothing() {
        changeCount = 0
        engine.deleteProject(UUID())
        XCTAssertEqual(changeCount, 0)
    }

    func testDeletingATaskClearsItFromItsProjectsOrder() {
        let project = engine.addProject(name: "Hop")
        let a = engine.addTask(name: "a", projectID: project)
        let b = engine.addTask(name: "b", projectID: project)

        engine.deleteTask(a)

        XCTAssertEqual(engine.data.projects.first?.taskOrder, [b])
    }

    // MARK: - Moving tasks between levels

    func testATaskMovesIntoAProjectAtAGivenPlace() {
        let project = engine.addProject(name: "Hop")
        let first = engine.addTask(name: "first", projectID: project)
        let second = engine.addTask(name: "second", projectID: project)
        let loose = engine.addTask(name: "loose")

        engine.moveTask(loose, toProject: project, at: 1)

        XCTAssertEqual(engine.tasks(in: project).map(\.id), [first, loose, second])
        XCTAssertFalse(engine.data.rootOrder.contains(loose))
    }

    func testATaskMovesBackOutToTheTopLevelKeepingItsHistory() {
        let project = engine.addProject(name: "Hop")
        let task = engine.addTask(name: "ship", projectID: project)
        engine.start(taskID: task)
        advance(1800)
        engine.stopActive()

        engine.moveTask(task, toProject: nil, at: 0)

        XCTAssertEqual(engine.data.rootOrder.first, task)
        XCTAssertNil(engine.data.tasks.first?.projectID)
        XCTAssertTrue(engine.tasks(in: project).isEmpty)
        XCTAssertEqual(engine.total(taskID: task), 1800)
    }

    func testMovingTheRunningTaskLeavesItRunning() {
        let project = engine.addProject(name: "Hop")
        let task = engine.addTask(name: "ship")
        engine.start(taskID: task)

        engine.moveTask(task, toProject: project)

        XCTAssertEqual(engine.activeTaskID, task)
        XCTAssertTrue(engine.isTracking(projectID: project))
    }

    func testAnOutOfRangeDestinationAppendsRatherThanFails() {
        let project = engine.addProject(name: "Hop")
        let first = engine.addTask(name: "first", projectID: project)
        let loose = engine.addTask(name: "loose")

        engine.moveTask(loose, toProject: project, at: 99)

        XCTAssertEqual(engine.tasks(in: project).map(\.id), [first, loose])
    }

    func testMovingAnUnknownTaskOrIntoAnUnknownProjectChangesNothing() {
        let task = engine.addTask(name: "loose")
        changeCount = 0

        engine.moveTask(UUID(), toProject: nil)
        engine.moveTask(task, toProject: UUID())

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(engine.data.rootOrder, [task])
    }

    func testTasksReorderInsideTheirProject() {
        let project = engine.addProject(name: "Hop")
        let a = engine.addTask(name: "a", projectID: project)
        let b = engine.addTask(name: "b", projectID: project)
        let c = engine.addTask(name: "c", projectID: project)

        engine.moveTaskInProject(project, from: 0, to: 2)
        XCTAssertEqual(engine.tasks(in: project).map(\.id), [b, c, a])

        engine.moveTaskInProject(project, from: 0, to: 99)   // clamps to the end
        XCTAssertEqual(engine.tasks(in: project).map(\.id), [c, a, b])
    }

    func testReorderingWithABadIndexOrProjectSavesNothing() {
        let project = engine.addProject(name: "Hop")
        engine.addTask(name: "a", projectID: project)
        changeCount = 0

        engine.moveTaskInProject(project, from: 99, to: 0)
        engine.moveTaskInProject(UUID(), from: 0, to: 0)

        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - The week

    /// Builds a single-task engine with a ready-made history — `data` is
    /// read-only from out here, which is the point of it.
    private func engineWithHistory(
        taskID: UUID, at moment: Date,
        intervals: [TrackerInterval] = [], corrections: [TrackerCorrection] = []
    ) -> TrackerEngine {
        clock = moment
        return TrackerEngine(data: TrackerData(
            projects: [], tasks: [TrackerTask(id: taskID, name: "t")],
            intervals: intervals, corrections: corrections, rootOrder: [taskID]
        ), now: { self.clock }, calendar: calendar)
    }

    func testTheWeekCountsFromItsFirstDay() {
        // the test calendar starts weeks on Sunday; 2026-07-17 is a Friday
        let task = UUID()
        engine = engineWithHistory(taskID: task, at: date(2026, 7, 17, 12, 0), intervals: [
            // Tuesday, inside this week
            TrackerInterval(taskID: task, start: date(2026, 7, 14, 9, 0), end: date(2026, 7, 14, 11, 0)),
            // the Friday before, outside it
            TrackerInterval(taskID: task, start: date(2026, 7, 10, 9, 0), end: date(2026, 7, 10, 12, 0)),
        ])

        XCTAssertEqual(engine.week(taskID: task), 2 * 3600)
        XCTAssertEqual(engine.total(taskID: task), 5 * 3600)
        XCTAssertEqual(engine.today(taskID: task), 0)
    }

    func testAnIntervalRunningIntoThisWeekIsCountedFromItsStart() {
        let task = UUID()
        // Monday 01:00, the week began Sunday 00:00
        engine = engineWithHistory(taskID: task, at: date(2026, 7, 13, 1, 0), intervals: [
            TrackerInterval(taskID: task, start: date(2026, 7, 11, 23, 0), end: date(2026, 7, 12, 1, 0)),
        ])
        // one of those two hours falls after Sunday midnight
        XCTAssertEqual(engine.week(taskID: task), 1 * 3600)
    }

    func testTheOpenIntervalCountsIntoTheWeekUpToNow() {
        let task = UUID()
        engine = engineWithHistory(taskID: task, at: date(2026, 7, 17, 12, 0), intervals: [
            TrackerInterval(taskID: task, start: date(2026, 7, 17, 10, 0)),
        ])
        XCTAssertEqual(engine.week(taskID: task), 2 * 3600)
    }

    func testCorrectionsCountIntoTheWeekTheyAreDated() {
        let task = UUID()
        engine = engineWithHistory(taskID: task, at: date(2026, 7, 17, 12, 0), corrections: [
            TrackerCorrection(taskID: task, day: date(2026, 7, 14, 0, 0), seconds: 45 * 60),
            TrackerCorrection(taskID: task, day: date(2026, 7, 6, 0, 0), seconds: 90 * 60),
        ])
        XCTAssertEqual(engine.week(taskID: task), 45 * 60)
    }

    func testEditingTheWeekLandsAsACorrectionDatedToday() {
        let task = UUID()
        engine = engineWithHistory(taskID: task, at: date(2026, 7, 17, 12, 0), intervals: [
            TrackerInterval(taskID: task, start: date(2026, 7, 14, 9, 0), end: date(2026, 7, 14, 11, 0)),
        ])

        XCTAssertTrue(engine.set(taskID: task, period: .week, to: 3 * 3600))

        XCTAssertEqual(engine.week(taskID: task), 3 * 3600)
        XCTAssertEqual(engine.today(taskID: task), 1 * 3600)   // the delta is dated today
        XCTAssertEqual(engine.data.corrections.first?.day, date(2026, 7, 17, 0, 0))
    }

    func testTheWeekIsNotEditedWhileTheTaskIsRunning() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        XCTAssertFalse(engine.set(taskID: task, period: .week, to: 3600))
        XCTAssertTrue(engine.data.corrections.isEmpty)
    }

    func testEditingTheWeekToWhatItAlreadyIsSavesNothing() {
        let task = engine.addTask(name: "t")
        changeCount = 0
        XCTAssertTrue(engine.setWeek(taskID: task, to: 0))
        XCTAssertEqual(changeCount, 0)
    }

    func testAProjectAddsUpItsTasksOverEveryPeriod() {
        let project = UUID(); let a = UUID(); let b = UUID(); let outside = UUID()
        clock = date(2026, 7, 17, 12, 0)
        engine = TrackerEngine(data: TrackerData(
            projects: [TrackerProject(id: project, name: "Hop")],
            tasks: [
                TrackerTask(id: a, projectID: project, name: "a"),
                TrackerTask(id: b, projectID: project, name: "b"),
                TrackerTask(id: outside, name: "outside"),
            ],
            intervals: [
                TrackerInterval(taskID: a, start: date(2026, 7, 17, 9, 0), end: date(2026, 7, 17, 10, 0)),
                TrackerInterval(taskID: b, start: date(2026, 7, 14, 9, 0), end: date(2026, 7, 14, 11, 0)),
                TrackerInterval(taskID: b, start: date(2026, 7, 1, 9, 0), end: date(2026, 7, 1, 13, 0)),
                TrackerInterval(taskID: outside, start: date(2026, 7, 17, 8, 0), end: date(2026, 7, 17, 9, 0)),
            ],
            corrections: [], rootOrder: [project, outside]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertEqual(engine.amount(projectID: project, period: .today), 1 * 3600)
        XCTAssertEqual(engine.amount(projectID: project, period: .week), 3 * 3600)
        XCTAssertEqual(engine.amount(projectID: project, period: .total), 7 * 3600)
        XCTAssertEqual(engine.amount(projectID: UUID(), period: .total), 0)
    }

    // MARK: - The task's own history

    func testEverySessionShowsUpNewestFirst() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        advance(600)
        engine.stopActive()
        advance(60)
        engine.start(taskID: task)
        advance(300)
        engine.stopActive()

        let history = engine.history(taskID: task)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.seconds, 300)
        XCTAssertEqual(history.last?.seconds, 600)
    }

    func testTheRunningSessionIsInTheHistoryAndSaysSo() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        advance(120)

        let entry = engine.history(taskID: task).first
        XCTAssertEqual(entry?.seconds, 120)
        XCTAssertEqual(entry?.isRunning, true)
    }

    func testAnAdjustmentAppearsBesideTheSessions() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        advance(600)
        engine.stopActive()
        engine.setTotal(taskID: task, to: 900)

        let history = engine.history(taskID: task)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map(\.seconds).reduce(0, +), engine.total(taskID: task))
        XCTAssertTrue(history.contains { if case .adjustment = $0.kind { return true } else { return false } })
    }

    func testOneTasksHistoryIsNotAnothers() {
        let a = engine.addTask(name: "a")
        let b = engine.addTask(name: "b")
        engine.start(taskID: a)
        advance(60)
        engine.stopActive()

        XCTAssertEqual(engine.history(taskID: a).count, 1)
        XCTAssertTrue(engine.history(taskID: b).isEmpty)
    }

    // MARK: - Adding a session by hand

    func testASessionCanBeAddedForWorkNobodyPressedPlayFor() {
        let task = engine.addTask(name: "t")

        XCTAssertNotNil(engine.addSession(taskID: task, seconds: 3600))

        XCTAssertEqual(engine.total(taskID: task), 3600)
        XCTAssertEqual(engine.today(taskID: task), 3600)
        XCTAssertEqual(engine.history(taskID: task).count, 1)
    }

    func testAnAddedSessionEndsWhenItIsSaidTo() {
        let task = engine.addTask(name: "t")
        clock = date(2026, 7, 17, 12, 0)
        engine.addSession(taskID: task, seconds: 1800, endingAt: date(2026, 7, 14, 10, 0))

        // it belongs to that Tuesday, not to today
        XCTAssertEqual(engine.today(taskID: task), 0)
        XCTAssertEqual(engine.week(taskID: task), 1800)
    }

    func testAnEmptySessionOrAnUnknownTaskAddsNothing() {
        let task = engine.addTask(name: "t")
        changeCount = 0
        XCTAssertNil(engine.addSession(taskID: task, seconds: 0))
        XCTAssertNil(engine.addSession(taskID: UUID(), seconds: 600))
        XCTAssertEqual(changeCount, 0)
    }

    // MARK: - Editing and deleting a line

    func testEditingASessionKeepsItsStartAndMovesItsEnd() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        advance(600)
        engine.stopActive()
        let entry = engine.history(taskID: task).first!

        XCTAssertTrue(engine.setEntryDuration(entry.id, to: 900))

        XCTAssertEqual(engine.total(taskID: task), 900)
        XCTAssertEqual(engine.history(taskID: task).first?.moment, entry.moment)
    }

    func testTheRunningSessionRefusesToBeEdited() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        advance(60)
        let entry = engine.history(taskID: task).first!

        XCTAssertFalse(engine.setEntryDuration(entry.id, to: 3600))
        XCTAssertEqual(engine.total(taskID: task), 60)
    }

    func testAnAdjustmentCanBeEditedToo() {
        let task = engine.addTask(name: "t")
        engine.setTotal(taskID: task, to: 600)
        let entry = engine.history(taskID: task).first!

        XCTAssertTrue(engine.setEntryDuration(entry.id, to: 1200))
        XCTAssertEqual(engine.total(taskID: task), 1200)
    }

    func testEditingToWhatItAlreadyIsSavesNothing() {
        let task = engine.addTask(name: "t")
        engine.addSession(taskID: task, seconds: 600)
        let entry = engine.history(taskID: task).first!
        changeCount = 0

        XCTAssertTrue(engine.setEntryDuration(entry.id, to: 600))
        XCTAssertEqual(changeCount, 0)
    }

    func testEditingSomethingThatIsNotThereChangesNothing() {
        changeCount = 0
        XCTAssertFalse(engine.setEntryDuration(UUID(), to: 600))
        XCTAssertEqual(changeCount, 0)
    }

    func testDeletingASessionTakesItsTimeWithIt() {
        let task = engine.addTask(name: "t")
        engine.addSession(taskID: task, seconds: 600)
        engine.addSession(taskID: task, seconds: 300)
        let entry = engine.history(taskID: task).first!

        engine.deleteEntry(entry.id)

        XCTAssertEqual(engine.history(taskID: task).count, 1)
        XCTAssertEqual(engine.total(taskID: task), 600)
    }

    func testDeletingTheRunningSessionStopsTheClock() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        advance(60)
        let entry = engine.history(taskID: task).first!

        engine.deleteEntry(entry.id)

        XCTAssertNil(engine.activeTaskID)
        XCTAssertEqual(engine.total(taskID: task), 0)
    }

    func testDeletingAnAdjustmentUndoesTheHandEdit() {
        let task = engine.addTask(name: "t")
        engine.addSession(taskID: task, seconds: 600)
        engine.setTotal(taskID: task, to: 1800)
        let adjustment = engine.history(taskID: task).first {
            if case .adjustment = $0.kind { return true } else { return false }
        }!

        engine.deleteEntry(adjustment.id)

        XCTAssertEqual(engine.total(taskID: task), 600)
    }

    func testDeletingNothingSavesNothing() {
        changeCount = 0
        engine.deleteEntry(UUID())
        XCTAssertEqual(changeCount, 0)
    }

    func testDeletingATaskTakesItsHistoryWithIt() {
        let task = engine.addTask(name: "t")
        engine.addSession(taskID: task, seconds: 600)
        engine.deleteTask(task)
        XCTAssertTrue(engine.data.intervals.isEmpty)
    }

    func testATasksPeriodFiguresMatchTheirOwnAccessors() {
        let task = engine.addTask(name: "t")
        engine.start(taskID: task)
        advance(120)
        engine.stopActive()

        XCTAssertEqual(engine.amount(taskID: task, period: .today), engine.today(taskID: task))
        XCTAssertEqual(engine.amount(taskID: task, period: .week), engine.week(taskID: task))
        XCTAssertEqual(engine.amount(taskID: task, period: .total), engine.total(taskID: task))
    }
}
