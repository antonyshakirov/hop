import AppKit
import HopCore
import os
@preconcurrency import UserNotifications

/// Turns the to-do list's reminders into system notifications and routes the
/// banner's buttons back into the list.
///
/// ONE pending request per item, always for its NEXT firing only: a weekday
/// repeat costs one slot instead of seven, which keeps the app far below the
/// system's 64-request ceiling. The model, not the notification, is the truth —
/// a reminder that arrives while banners are switched off still shows up in the
/// list, because `TodosController.reconcile` runs off its own ticker.
@MainActor
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let categoryID = "hop.reminder"
    static let snoozeAction = "hop.reminder.snooze"
    static let doneAction = "hop.reminder.done"
    /// How far the banner's snooze pushes a firing.
    static let snoozeInterval: TimeInterval = 10 * 60
    /// The system ceiling is 64 pending requests; leave headroom for everything
    /// else the app may post.
    private static let maxPending = 60

    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "Reminders")
    private weak var todos: TodosController?

    /// Registers the two banner buttons and starts taking delivery callbacks.
    /// Skipped in a bundle-less run: UNUserNotificationCenter crashes outright
    /// there (the same guard `Alerts` already carries).
    func install(todos: TodosController) {
        self.todos = todos
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let lang = L10n.current
        let snooze = UNNotificationAction(identifier: Self.snoozeAction,
                                          title: L10n.t(.remindSnooze, lang).capitalizedFirst,
                                          options: [])
        let done = UNNotificationAction(identifier: Self.doneAction,
                                        title: L10n.t(.remindDone, lang).capitalizedFirst,
                                        options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [snooze, done],
                                   intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        reschedule(todos.list)
    }

    /// Replaces every pending reminder request with one per item that still has a
    /// firing ahead of it — nearest first, capped.
    func reschedule(_ list: TodoList) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: list.items.map(\.id.uuidString))
        // the drop above silences what was armed; the reminders themselves keep
        guard UserDefaults.standard.bool(forKey: SettingsKey.todoRemindBanner),
              ModuleActivation.isOn("todos") else { return }

        let now = Date()
        let due = list.items
            .compactMap { item -> (TodoItem, Date)? in
                guard let at = RemindSchedule.effectiveFiring(item), at > now else { return nil }
                return (item, at)
            }
            .sorted { $0.1 < $1.1 }

        if due.count > Self.maxPending {
            // Never drop silently: the ones past the cap are picked up by the next
            // reschedule, but the log says so rather than pretending all are armed.
            Self.log.info("reminders: scheduling \(Self.maxPending, privacy: .public) of \(due.count, privacy: .public)")
        }

        for (item, at) in due.prefix(Self.maxPending) {
            let content = UNMutableNotificationContent()
            content.title = item.text.capitalizedFirst
            // A task with no comment gets no body line — filler text would be noise.
            if !item.note.isEmpty { content.body = item.note }
            content.categoryIdentifier = Self.categoryID
            // Silent by design: the app plays its own alert sound from the tick
            // that detects the firing, so the two can never double up and the
            // `sound` setting keeps working with banners switched off.
            content.sound = nil
            let fields = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                         from: at)
            center.add(UNNotificationRequest(
                identifier: item.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: fields, repeats: false)))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// The banner's buttons write straight into the list: the notification is a
    /// surface, the list is the state.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = UUID(uuidString: response.notification.request.identifier)
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            guard let id, let todos else { return }
            switch action {
            case Self.snoozeAction:
                todos.snooze(id, until: Date().addingTimeInterval(Self.snoozeInterval))
            case Self.doneAction:
                if todos.list.items.first(where: { $0.id == id })?.done == false {
                    todos.toggle(id)
                }
            default:
                break   // tapping the banner itself just brings the app forward
            }
        }
    }

    /// Show the banner even while Hop is frontmost — the panel is usually closed,
    /// and "frontmost" here means a settings window nobody is looking at.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The banner IS the moment. Bring the model level with it now rather than
        // on the next sweep, so the sound, the struck-through time and the
        // menu-bar dot all land together with it.
        Task { @MainActor in todos?.reconcile() }
        completionHandler([.banner])
    }
}
