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

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.storageIdentifier
        storeDir = base.appendingPathComponent(id, isDirectory: true)
        // A snapshot/demo render must never load real user data — start empty
        // and let the --tasks seed stage its own deterministic content.
        list = Snapshot.active ? .empty : TodosStore.load(from: storeDir)
    }

    /// Appends a to-do; a blank text is a no-op (the model trims and rejects
    /// it), so nothing is saved for an empty commit.
    func add(text: String) {
        guard list.add(text: text) != nil else { return }
        save()
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
    func reorder(dragging id: UUID, toDisplayInsertion index: Int) {
        list.reorderInDisplay(dragging: id, toDisplayInsertion: index)
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
    /// so an idle tick costs nothing.
    func reconcile(now: Date = Date()) {
        guard list.reconcileReminders(now: now) else { return }
        save()
        reschedule()
    }

    /// The panel was opened and the rows blinked — the firings have been seen.
    func acknowledgeFirings() {
        guard list.acknowledgeFirings() else { return }
        save()
    }

    /// Filled in by ReminderScheduler once notifications are wired up.
    private func reschedule() {}

    private func save() {
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        do {
            try TodosStore.save(list, to: storeDir)
        } catch {
            // One line per failure — no spam (mirrors TrackerController).
            Self.log.error("todos save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
