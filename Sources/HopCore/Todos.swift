import Foundation

/// A single to-do: text plus a done flag. New items append at the bottom and
/// toggling `done` never reorders — a completed item keeps its place.
public struct TodoItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

/// The persisted to-do list: an ordered set of items. `add` appends, `toggle`
/// and `delete` address items by id and preserve order.
public struct TodoList: Codable, Equatable {
    public var items: [TodoItem]

    public static let empty = TodoList(items: [])

    public init(items: [TodoItem] = []) {
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case items }

    /// `items` is decoded leniently so a file saved as `{}` (or by an older
    /// build that omitted the key) still loads as an empty list instead of
    /// failing to decode and being backed up as if it were corrupt.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([TodoItem].self, forKey: .items) ?? []
    }

    /// Appends a new item at the BOTTOM. The text is whitespace-trimmed; an
    /// empty or whitespace-only text is a no-op (returns nil), so a stray
    /// commit never inserts a blank row.
    @discardableResult
    public mutating func add(text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TodoItem(text: trimmed)
        items.append(item)
        return item.id
    }

    /// Flips the item's `done` flag in place — its position is preserved, so a
    /// completed item never jumps around the list. No-op for an unknown id.
    public mutating func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
    }

    /// Removes the item. No-op for an unknown id.
    public mutating func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Moves the item at `from` to `to`. `from` out of range is a no-op; `to`
    /// is clamped into range after the item is lifted out. Backs the drag
    /// reorder in TodosView.
    public mutating func move(from: Int, to: Int) {
        guard items.indices.contains(from) else { return }
        let item = items.remove(at: from)
        let clamped = max(0, min(to, items.count))
        items.insert(item, at: clamped)
    }
}
