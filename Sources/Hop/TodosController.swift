import Combine
import Foundation
import HopCore
import os

/// Owns the on-disk to-do list: loads `todos.json` at launch and saves on
/// every mutation. Mirrors `TrackerController` minus the ticker — a to-do
/// list has nothing that ticks, so there is no heartbeat or timer here.
@MainActor
final class TodosController: ObservableObject {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "TodosController")
    /// "visible rows" cap: always active, 3…15, default 10 — the list caps to a
    /// fixed height with inner scroll. A stored 0 (legacy "all") reads as the
    /// default on load.
    static let visibleRowsKey = "todosVisibleRows"
    static let defaultVisibleRows = RowCap.defaultRows
    /// The list is a plain value; publishing it is enough for views observing
    /// this controller to redraw (no nested engine to forward, unlike the
    /// tracker). AppModel forwards this controller's objectWillChange onward.
    @Published private(set) var list: TodoList

    /// Same Application Support/bundle-id folder the other modules persist
    /// into; TodosStore appends todos.json itself.
    private let storeDir: URL

    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.storageIdentifier
        storeDir = base.appendingPathComponent(id, isDirectory: true)
        // A snapshot/demo render must never load real user data — start empty
        // and let the --tasks seed stage its own deterministic content.
        list = (Snapshot.active || demo) ? .empty : TodosStore.load(from: storeDir)
        // Switching the module off drops every armed banner, and switching it
        // back on arms them again from the same reminders.
        NotificationCenter.default.addObserver(
            forName: ModuleActivation.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reschedule() }
        }
    }

    /// Appends a to-do; a blank text is a no-op (the model trims and rejects
    /// it), so nothing is saved for an empty commit.
    /// Returns the new item's id so a caller that has more to set — a note, a
    /// reminder — can address it without searching for it by text.
    @discardableResult
    func add(text: String) -> UUID? {
        guard let id = list.add(text: text) else { return nil }
        save()
        return id
    }

    func toggle(_ id: UUID) {
        list.toggle(id)
        save()
    }

    func delete(_ id: UUID) {
        list.delete(id)
        save()
    }

    /// Reorders the list for a whole-row drag in the DISPLAYED list (active items
    /// first, then completed). `toDisplayInsertion` is the drop index among the
    /// other displayed items; the model clamps it to the dragged item's group so
    /// a drag never crosses the active/completed boundary. Saved like every other
    /// mutation.
    func reorder(dragging id: UUID, toDisplayInsertion index: Int, importantFirst: Bool = false) {
        list.reorderInDisplay(dragging: id, toDisplayInsertion: index,
                              importantFirst: importantFirst)
        save()
    }

    func setText(_ id: UUID, to text: String) {
        list.setText(id, to: text)
        save()
    }

    func setNote(_ id: UUID, to note: String) {
        list.setNote(id, to: note)
        save()
    }

    func setImportant(_ id: UUID, _ value: Bool) {
        list.setImportant(id, value)
        save()
    }

    func setReminder(_ id: UUID, at date: Date, repeatDays: [Int]) {
        list.setReminder(id, at: date, repeatDays: repeatDays)
        save()
        reschedule()
    }

    func clearReminder(_ id: UUID) {
        list.clearReminder(id)
        save()
        reschedule()
    }

    func snooze(_ id: UUID, until date: Date) {
        list.snooze(id, until: date)
        save()
        reschedule()
    }

    /// Brings the list up to date — at launch, on wake, on the tick and when the
    /// panel opens. Saves and re-schedules only when a reminder actually came due,
    /// so an idle tick costs nothing. The alert sound is played HERE rather than
    /// by the notification, so it works with banners switched off and can never
    /// double up with one.
    func reconcile(now: Date = Date()) {
        let before = Set(list.items.filter(\.firedUnseen).map(\.id))
        guard list.reconcileReminders(now: now) else {
            scheduleNextFiring()
            return
        }
        let fired = Set(list.items.filter(\.firedUnseen).map(\.id)).subtracting(before)
        save()
        reschedule()
        if !fired.isEmpty,
           UserDefaults.standard.bool(forKey: SettingsKey.todoRemindSound),
           ModuleActivation.isOn("todos") {
            Sounds.alarm()
        }
    }

    /// The panel was opened and the rows blinked — the firings have been seen.
    func acknowledgeFirings() {
        guard list.acknowledgeFirings() else { return }
        save()
    }

    /// Adopts the file's version of the list after something outside the app
    /// changed it — the user's agent, a script, a synced folder. The app's own
    /// saves land here too, so an identical list is a no-op rather than a redraw.
    func reloadFromDisk() {
        guard !Snapshot.active else { return }
        let onDisk = TodosStore.load(from: storeDir)
        guard onDisk != list else { return }
        list = onDisk
        reconcile()
        reschedule()
    }

    var storeDirectory: URL { storeDir }

    /// Fires exactly when the next reminder is due, instead of waiting for the
    /// next sweep. The sweep alone meant a reminder could land up to 15 seconds
    /// late — the banner arrived, the blue dot and the sound followed a while
    /// after, which read as two unrelated events (Anton, 2026-07-28).
    private var nextFiringTimer: Timer?

    private func scheduleNextFiring() {
        nextFiringTimer?.invalidate()
        nextFiringTimer = nil
        let now = Date()
        guard let next = list.items
            .compactMap({ RemindSchedule.effectiveFiring($0) })
            .filter({ $0 > now })
            .min() else { return }
        // a breath past the moment itself, so the comparison inside reconcile is
        // unambiguous
        let timer = Timer(timeInterval: max(0.2, next.timeIntervalSince(now) + 0.3),
                          repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        nextFiringTimer = timer
    }

    /// Wired to `ReminderScheduler.reschedule` at launch. A closure rather than a
    /// direct reference so the store stays free of UserNotifications, and so a
    /// snapshot or bundle-less run simply has nothing attached.
    var onRemindersChanged: ((TodoList) -> Void)?

    private func reschedule() {
        onRemindersChanged?(list)
        scheduleNextFiring()
    }

    private func save() {
        guard !demo else { return }
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        do {
            try TodosStore.save(list, to: storeDir)
        } catch {
            // One line per failure — no spam (mirrors TrackerController).
            Self.log.error("todos save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
