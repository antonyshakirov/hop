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

    // MARK: - Flatten migration (projects die on load)

    /// The required fixture: 2 projects + root tasks + an ACTIVE task inside a
    /// project. Every task becomes a root task; the flat order follows the old
    /// rootOrder, expanding each project's tasks in place (internal order kept);
    /// projects empty; intervals/corrections/open interval all survive.
    func testFlattenExpandsProjectsInPlacePreservingAllHistory() {
        let p1 = UUID(); let p2 = UUID()
        let t1a = UUID(); let t1b = UUID()   // inside p1
        let t2a = UUID()                     // inside p2, ACTIVE
        let r1 = UUID(); let r2 = UUID()     // root tasks
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
            // project, root task, project, root task
            rootOrder: [p1, r1, p2, r2]
        ), now: { self.clock }, calendar: calendar)

        // projects gone, every task detached
        XCTAssertTrue(engine.data.projects.isEmpty)
        XCTAssertTrue(engine.data.tasks.allSatisfy { $0.projectID == nil })
        // flat order: p1's tasks in place, then r1, then p2's task, then r2
        XCTAssertEqual(engine.data.rootOrder, [t1a, t1b, r1, t2a, r2])
        // the active task inside p2 is still active
        XCTAssertEqual(engine.activeTaskID, t2a)
        XCTAssertEqual(engine.activeIntervalStart, date(2026, 7, 17, 11, 0))
        // all history survives
        XCTAssertEqual(engine.total(taskID: t1a), 1 * 3600)
        XCTAssertEqual(engine.total(taskID: t1b), 30 * 60)
        XCTAssertEqual(engine.total(taskID: t2a), 1 * 3600)   // open interval 11:00 -> 12:00
        XCTAssertEqual(engine.total(taskID: r1), 5 * 60)
        XCTAssertEqual(engine.data.intervals.count, 2)
        XCTAssertEqual(engine.data.corrections.count, 2)
    }

    /// A pre-8.5 file has no rootOrder: flatten derives it as the projects in
    /// their array order (each expanded to its tasks), then any root tasks.
    func testFlattenWithNoRootOrderDerivesProjectsThenRootTasks() {
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

        XCTAssertEqual(engine.data.rootOrder, [t1, t2, root])
        XCTAssertTrue(engine.data.projects.isEmpty)
    }

    func testFlattenIsANoOpWhenAlreadyFlat() {
        let a = UUID(); let b = UUID()
        engine = TrackerEngine(data: TrackerData(
            projects: [],
            tasks: [TrackerTask(id: a, name: "A"), TrackerTask(id: b, name: "B")],
            intervals: [], corrections: [], rootOrder: [b, a]
        ), now: { self.clock }, calendar: calendar)

        XCTAssertTrue(engine.data.projects.isEmpty)
        XCTAssertEqual(engine.data.rootOrder, [b, a])   // existing flat order untouched
        XCTAssertTrue(engine.data.tasks.allSatisfy { $0.projectID == nil })
    }

    /// Anton's live pre-flatten tracker.json shape (nested tasks, open interval,
    /// corrections, expanded flags, NO rootOrder) loads and flattens losslessly.
    func testOldFileShapeLoadsAndFlattensLosslessly() throws {
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

        // projects flattened away; the two nested tasks become root tasks in
        // project (then task) order
        XCTAssertTrue(engine.data.projects.isEmpty)
        XCTAssertEqual(engine.data.rootOrder, [t1, t2])
        XCTAssertTrue(engine.data.tasks.allSatisfy { $0.projectID == nil })
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
}
