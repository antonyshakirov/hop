import Foundation

/// A single to-do: text plus a done flag. New items append at the bottom and
/// toggling `done` never reorders — a completed item keeps its place.
public struct TodoItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var text: String
    public var done: Bool
    /// Free-form comment shown in the expanded card; empty = the collapsed row
    /// draws no note glyph.
    public var note: String
    /// The next firing. nil = no reminder.
    public var remindAt: Date?
    /// Repeat weekdays in Calendar numbering (1 = Sunday). Empty = one-shot.
    public var repeatDays: [Int]
    /// Set by the banner's snooze; supersedes `remindAt` until it passes.
    public var snoozedUntil: Date?
    /// When the reminder last fired. Never displayed — it is what makes a firing
    /// happen ONCE: a one-shot's `remindAt` stays in the past forever, so without
    /// this every relaunch would treat it as a fresh firing.
    public var firedAt: Date?
    /// A firing the user has not acknowledged yet — the row blinks and the menu
    /// bar carries its mark until it does.
    public var firedUnseen: Bool
    /// The importance mark. Whether it also sorts the list is a setting.
    public var important: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false,
                note: String = "", remindAt: Date? = nil, repeatDays: [Int] = [],
                snoozedUntil: Date? = nil, firedAt: Date? = nil,
                firedUnseen: Bool = false, important: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
        self.note = note
        self.remindAt = remindAt
        self.repeatDays = Self.normalizedWeekdays(repeatDays)
        self.snoozedUntil = snoozedUntil
        self.firedAt = firedAt
        self.firedUnseen = firedUnseen
        self.important = important
    }

    /// Weekdays sorted, de-duplicated and range-checked, so a hand-edited or
    /// older file can never feed Calendar an impossible weekday.
    public static func normalizedWeekdays(_ days: [Int]) -> [Int] {
        Array(Set(days.filter { (1...7).contains($0) })).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, done, note, remindAt, repeatDays, snoozedUntil,
             firedAt, firedUnseen, important
    }

    /// Every field added after the checklist shipped decodes leniently: an older
    /// todos.json has none of them and must still load, since a decode failure
    /// moves the user's list aside as a .bak.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        remindAt = try container.decodeIfPresent(Date.self, forKey: .remindAt)
        repeatDays = Self.normalizedWeekdays(
            try container.decodeIfPresent([Int].self, forKey: .repeatDays) ?? [])
        snoozedUntil = try container.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        firedAt = try container.decodeIfPresent(Date.self, forKey: .firedAt)
        firedUnseen = try container.decodeIfPresent(Bool.self, forKey: .firedUnseen) ?? false
        important = try container.decodeIfPresent(Bool.self, forKey: .important) ?? false
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

    /// Every id-taking mutator no-ops on an unknown id — the engine invariant the
    /// tracker already follows, so a stale row in a view can never write nonsense.
    private mutating func mutate(_ id: UUID, _ body: (inout TodoItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
    }

    /// Renames the item. A blank commit is rejected rather than stored, the same
    /// rule `add` follows.
    public mutating func setText(_ id: UUID, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id) { $0.text = trimmed }
    }

    /// The comment is stored as typed apart from the outer whitespace — the line
    /// breaks inside it are the user's own.
    public mutating func setNote(_ id: UUID, to note: String) {
        mutate(id) { $0.note = note.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Arms or re-arms the reminder. Re-arming clears the previous firing: a new
    /// time is a new promise, not an old one that already went off.
    public mutating func setReminder(_ id: UUID, at date: Date, repeatDays: [Int]) {
        mutate(id) {
            $0.remindAt = date
            $0.repeatDays = TodoItem.normalizedWeekdays(repeatDays)
            $0.snoozedUntil = nil
            $0.firedAt = nil
            $0.firedUnseen = false
        }
    }

    public mutating func clearReminder(_ id: UUID) {
        mutate(id) {
            $0.remindAt = nil
            $0.repeatDays = []
            $0.snoozedUntil = nil
            $0.firedAt = nil
            $0.firedUnseen = false
        }
    }

    /// Pushes this firing later. Snoozing is itself an acknowledgement — the user
    /// has seen the banner — so the unseen mark clears with it.
    public mutating func snooze(_ id: UUID, until date: Date) {
        mutate(id) {
            $0.snoozedUntil = date
            $0.firedUnseen = false
        }
    }

    public mutating func setImportant(_ id: UUID, _ value: Bool) {
        mutate(id) { $0.important = value }
    }

    /// Clears every unseen firing (the panel was opened and the rows blinked).
    /// True when anything changed, so the caller only saves when there is a
    /// reason to.
    @discardableResult
    public mutating func acknowledgeFirings() -> Bool {
        guard hasUnseenFiring else { return false }
        for index in items.indices { items[index].firedUnseen = false }
        return true
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
