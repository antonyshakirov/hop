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

    /// Reorders the list (drag). Clamped in the model; `from` out of range is a
    /// model no-op — we still save, mirroring toggle/delete.
    func move(from: Int, to: Int) {
        list.move(from: from, to: to)
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
