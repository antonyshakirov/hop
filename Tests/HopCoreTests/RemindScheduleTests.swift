import XCTest
@testable import HopCore

/// Reminder arithmetic: when a repeating reminder fires next, what a firing does
/// to an item, and how a list is brought back to a truthful state after the Mac
/// was asleep or shut down.
final class RemindScheduleTests: XCTestCase {

    // A fixed calendar and zone so the assertions do not drift with the machine.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = cal.locale
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: string)!
    }

    // MARK: - next()

    func testNextIsLaterTodayWhenTodayIsListedAndTheTimeHasNotPassed() {
        // 2026-07-28 is a Tuesday (weekday 3).
        let next = RemindSchedule.next(after: date("2026-07-28 09:00"), hour: 15, minute: 0,
                                       weekdays: [3], calendar: cal)
        XCTAssertEqual(next, date("2026-07-28 15:00"))
    }

    func testNextSkipsToTheNextListedDayWhenTodaysTimeHasPassed() {
        // Tuesday 16:00, repeating Tue + Thu → Thursday.
        let next = RemindSchedule.next(after: date("2026-07-28 16:00"), hour: 15, minute: 0,
                                       weekdays: [3, 5], calendar: cal)
        XCTAssertEqual(next, date("2026-07-30 15:00"))
    }

    func testNextWrapsAcrossTheWeekEnd() {
        // Saturday, repeating Mondays only → the coming Monday.
        let next = RemindSchedule.next(after: date("2026-08-01 20:00"), hour: 8, minute: 30,
                                       weekdays: [2], calendar: cal)
        XCTAssertEqual(next, date("2026-08-03 08:30"))
    }

    func testNextWithASingleWeekdayIsAFullWeekLater() {
        let next = RemindSchedule.next(after: date("2026-07-28 15:01"), hour: 15, minute: 0,
                                       weekdays: [3], calendar: cal)
        XCTAssertEqual(next, date("2026-08-04 15:00"))
    }

    func testNextIsNilForAnEmptyWeekdaySet() {
        XCTAssertNil(RemindSchedule.next(after: date("2026-07-28 09:00"), hour: 15, minute: 0,
                                         weekdays: [], calendar: cal))
    }

    func testNextIgnoresImpossibleWeekdays() {
        // A hand-edited file could carry anything; 99 must not silently win.
        let next = RemindSchedule.next(after: date("2026-07-28 09:00"), hour: 15, minute: 0,
                                       weekdays: [99, 3], calendar: cal)
        XCTAssertEqual(next, date("2026-07-28 15:00"))
    }

    func testNextHandlesTheSpringForwardGap() {
        // Europe/Berlin loses 02:00–03:00 on 2027-03-28, a Sunday (weekday 1).
        // A 02:30 reminder must land on a real instant rather than vanish.
        let next = RemindSchedule.next(after: date("2027-03-27 12:00"), hour: 2, minute: 30,
                                       weekdays: [1], calendar: cal)
        XCTAssertNotNil(next)
        XCTAssertEqual(cal.component(.day, from: next!), 28)
    }

    // MARK: - fired()

    func testFiredOneShotKeepsItsTimeAndMarksUnseen() {
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 15:00"))

        let out = RemindSchedule.fired(item, now: date("2026-07-28 15:00"), calendar: cal)

        XCTAssertEqual(out.remindAt, date("2026-07-28 15:00"), "the past time stays, struck through")
        XCTAssertEqual(out.firedAt, date("2026-07-28 15:00"))
        XCTAssertTrue(out.firedUnseen)
        XCTAssertFalse(out.done)
    }

    func testFiredRepeatingRollsForwardAndUnticksDone() {
        let item = TodoItem(text: "a", done: true,
                            remindAt: date("2026-07-28 15:00"), repeatDays: [3, 5])

        let out = RemindSchedule.fired(item, now: date("2026-07-28 15:00"), calendar: cal)

        XCTAssertEqual(out.remindAt, date("2026-07-30 15:00"))
        XCTAssertFalse(out.done, "a repeating task comes back as active")
        XCTAssertTrue(out.firedUnseen)
    }

    func testFiredClearsASnooze() {
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 15:00"),
                            snoozedUntil: date("2026-07-28 15:10"))

        let out = RemindSchedule.fired(item, now: date("2026-07-28 15:10"), calendar: cal)

        XCTAssertNil(out.snoozedUntil)
    }

    // MARK: - reconcile()

    func testReconcileFiresAPastOneShotExactlyOnce() {
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 15:00"))

        let first = RemindSchedule.reconcile(item, now: date("2026-07-28 18:00"), calendar: cal)
        XCTAssertTrue(first.firedUnseen)

        // The user saw it and the app relaunches days later: it must NOT fire again.
        var seen = first
        seen.firedUnseen = false
        let second = RemindSchedule.reconcile(seen, now: date("2026-08-05 09:00"), calendar: cal)
        XCTAssertFalse(second.firedUnseen)
    }

    func testReconcileCollapsesAWeekOfMissedRepeatsIntoOneUnseenFiring() {
        // Mac off from Tue the 28th to Wed Aug 5th; daily reminder at 09:00.
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 09:00"),
                            repeatDays: [1, 2, 3, 4, 5, 6, 7])

        let out = RemindSchedule.reconcile(item, now: date("2026-08-05 12:00"), calendar: cal)

        XCTAssertTrue(out.firedUnseen)
        XCTAssertEqual(out.remindAt, date("2026-08-06 09:00"), "rolled to the next future slot")
    }

    func testReconcileLeavesAFutureReminderAlone() {
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 15:00"))

        let out = RemindSchedule.reconcile(item, now: date("2026-07-28 09:00"), calendar: cal)

        XCTAssertEqual(out, item)
    }

    func testReconcileLeavesAnItemWithoutAReminderAlone() {
        let item = TodoItem(text: "a", note: "no reminder here")

        let out = RemindSchedule.reconcile(item, now: date("2026-07-28 09:00"), calendar: cal)

        XCTAssertEqual(out, item)
    }

    func testReconcileFiresAPassedSnooze() {
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 15:00"),
                            snoozedUntil: date("2026-07-28 15:10"),
                            firedAt: date("2026-07-28 15:00"))

        let out = RemindSchedule.reconcile(item, now: date("2026-07-28 15:11"), calendar: cal)

        XCTAssertNil(out.snoozedUntil)
        XCTAssertTrue(out.firedUnseen)
    }

    func testReconcileLeavesALiveSnoozeAlone() {
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 15:00"),
                            snoozedUntil: date("2026-07-28 15:10"),
                            firedAt: date("2026-07-28 15:00"))

        let out = RemindSchedule.reconcile(item, now: date("2026-07-28 15:05"), calendar: cal)

        XCTAssertEqual(out, item)
    }

    // MARK: - replacing() — the bug that made a typed time silently wrong

    func testReplacingMinuteKeepsTheHourEvenWhenTheMinuteIsEarlier() {
        // The regression: Calendar's own date(bySetting:) returned 23:17 here.
        let out = RemindSchedule.replacing(.minute, with: 17,
                                           in: date("2026-07-28 22:30"), calendar: cal)
        XCTAssertEqual(out, date("2026-07-28 22:17"))
    }

    func testReplacingHourKeepsTheMinuteAndTheDay() {
        let out = RemindSchedule.replacing(.hour, with: 9,
                                           in: date("2026-07-28 22:30"), calendar: cal)
        XCTAssertEqual(out, date("2026-07-28 09:30"))
    }

    func testReplacingClampsOutOfRangeValues() {
        XCTAssertEqual(RemindSchedule.replacing(.hour, with: 99,
                                                in: date("2026-07-28 10:00"), calendar: cal),
                       date("2026-07-28 23:00"))
        XCTAssertEqual(RemindSchedule.replacing(.minute, with: -5,
                                                in: date("2026-07-28 10:30"), calendar: cal),
                       date("2026-07-28 10:00"))
    }

    func testReplacingAnythingElseLeavesTheDateAlone() {
        let original = date("2026-07-28 10:30")
        XCTAssertEqual(RemindSchedule.replacing(.day, with: 3, in: original, calendar: cal), original)
    }

    // MARK: - effectiveFiring()

    func testEffectiveFiringPrefersTheSnooze() {
        let item = TodoItem(text: "a", remindAt: date("2026-07-28 15:00"),
                            snoozedUntil: date("2026-07-28 15:10"))

        XCTAssertEqual(RemindSchedule.effectiveFiring(item), date("2026-07-28 15:10"))
    }

    func testEffectiveFiringIsNilWithoutAReminder() {
        XCTAssertNil(RemindSchedule.effectiveFiring(TodoItem(text: "a")))
    }

    // MARK: - list-level reconciliation

    func testListReconciliationReportsWhetherAnythingChanged() {
        var list = TodoList(items: [TodoItem(text: "a", remindAt: date("2026-07-28 15:00")),
                                    TodoItem(text: "b")])

        XCTAssertTrue(list.reconcileReminders(now: date("2026-07-28 16:00"), calendar: cal))
        XCTAssertTrue(list.hasUnseenFiring)

        XCTAssertFalse(list.reconcileReminders(now: date("2026-07-28 17:00"), calendar: cal),
                       "nothing left to fire — the caller must not save again")
    }
}
