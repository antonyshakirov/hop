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
    /// "visible rows" cap: 0 = all (default — preserves the uncapped list for
    /// existing users), 3…15 caps the list to a fixed height with inner scroll.
    static let visibleRowsKey = "todosVisibleRows"
    static let defaultVisibleRows = RowCap.all
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
