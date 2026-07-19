import Combine
import Foundation
import HopCore

/// Owns the on-disk to-do list: loads `todos.json` at launch and saves on
/// every mutation. Mirrors `TrackerController` minus the ticker — a to-do
/// list has nothing that ticks, so there is no heartbeat or timer here.
@MainActor
final class TodosController: ObservableObject {
    /// The list is a plain value; publishing it is enough for views observing
    /// this controller to redraw (no nested engine to forward, unlike the
    /// tracker). AppModel forwards this controller's objectWillChange onward.
    @Published private(set) var list: TodoList

    /// Same Application Support/bundle-id folder the other modules persist
    /// into; TodosStore appends todos.json itself.
    private let storeDir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? "com.antonshakirov.minimo"
        storeDir = base.appendingPathComponent(id, isDirectory: true)
        list = TodosStore.load(from: storeDir)
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

    private func save() {
        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        try? TodosStore.save(list, to: storeDir)
    }
}
