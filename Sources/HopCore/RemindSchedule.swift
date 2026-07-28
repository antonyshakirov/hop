import Foundation

/// Pure reminder arithmetic: when a repeating reminder fires next, what a firing
/// does to an item, and how a list is brought back to a truthful state after the
/// app was asleep or shut down. No AppKit and no UserNotifications — the
/// scheduler in the app layer asks these questions and only then talks to the
/// system, so every rule here is testable on its own.
public enum RemindSchedule {

    /// The next firing strictly after `date` for a weekday set and a time of day.
    /// nil for an empty set — a one-shot does not roll forward.
    public static func next(after date: Date, hour: Int, minute: Int,
                            weekdays: [Int], calendar: Calendar) -> Date? {
        let days = TodoItem.normalizedWeekdays(weekdays)
        guard !days.isEmpty else { return nil }
        var best: Date?
        for day in days {
            var components = DateComponents()
            components.weekday = day
            components.hour = hour
            components.minute = minute
            // .nextTime keeps a firing time that does not exist on a DST
            // spring-forward day from being skipped over entirely.
            guard let candidate = calendar.nextDate(after: date, matching: components,
                                                    matchingPolicy: .nextTime) else { continue }
            if best == nil || candidate < best! { best = candidate }
        }
        return best
    }

    /// A date with ONE clock component replaced, keeping the rest of it.
    ///
    /// Not `Calendar.date(bySetting:value:of:)`: that searches for the NEXT date
    /// whose component equals the value, so setting "17 minutes" on a 22:30 date
    /// returns 23:17. A reminder typed as 22:17 silently became an hour later and
    /// never fired (Anton, 2026-07-28).
    public static func replacing(_ component: Calendar.Component, with value: Int,
                                 in date: Date, calendar: Calendar) -> Date {
        var fields = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        switch component {
        case .hour: fields.hour = max(0, min(23, value))
        case .minute: fields.minute = max(0, min(59, value))
        default: return date
        }
        return calendar.date(from: fields) ?? date
    }

    /// The time the item actually fires next: a live snooze wins over the schedule.
    public static func effectiveFiring(_ item: TodoItem) -> Date? {
        item.snoozedUntil ?? item.remindAt
    }

    /// The item's state immediately after its reminder fired at `now`. A repeating
    /// item rolls to its next weekday AND comes back as active — a task that
    /// repeats is not finished just because last week's instance was ticked.
    public static func fired(_ item: TodoItem, now: Date, calendar: Calendar) -> TodoItem {
        var out = item
        out.snoozedUntil = nil
        out.firedAt = now
        out.firedUnseen = true
        if !item.repeatDays.isEmpty, let at = item.remindAt {
            let time = calendar.dateComponents([.hour, .minute], from: at)
            out.remindAt = next(after: now, hour: time.hour ?? 0, minute: time.minute ?? 0,
                                weekdays: item.repeatDays, calendar: calendar)
            out.done = false
        }
        return out
    }

    /// Brings one item up to date at launch, on wake and on every tick. A firing
    /// counts as NEW only while `firedAt` is older than the scheduled time, so a
    /// one-shot whose time is permanently in the past fires exactly once, and a
    /// repeating item that missed a week collapses into ONE unseen firing rather
    /// than a queue of them.
    public static func reconcile(_ item: TodoItem, now: Date, calendar: Calendar) -> TodoItem {
        var out = item
        if let snoozed = out.snoozedUntil, snoozed <= now {
            out.snoozedUntil = nil
            out.firedAt = now
            out.firedUnseen = true
        }
        if let at = out.remindAt, at <= now, (out.firedAt.map { $0 < at } ?? true) {
            out = fired(out, now: now, calendar: calendar)
        }
        return out
    }
}

public extension TodoList {
    /// Reconciles every item; true when anything changed, so the caller saves and
    /// re-schedules only when there is something to save.
    @discardableResult
    mutating func reconcileReminders(now: Date, calendar: Calendar = .current) -> Bool {
        let before = items
        items = items.map { RemindSchedule.reconcile($0, now: now, calendar: calendar) }
        return items != before
    }

    /// Any firing the user has not acknowledged — the source of the menu-bar mark.
    var hasUnseenFiring: Bool { items.contains(where: \.firedUnseen) }
}
