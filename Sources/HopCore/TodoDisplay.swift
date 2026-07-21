import Foundation

/// Pure display-ordering and drag-clamping for the to-do list. Completing an
/// item NEVER touches the stored order (`TodoList.items`); a completed item
/// merely sinks to the bottom for DISPLAY, so unchecking it returns it to its
/// slot for free. A whole-row drag reorders WITHIN a group (active or completed)
/// and never crosses the boundary between them.
public enum TodoDisplay {
    /// Items in display order: active items first (in stored order), then
    /// completed items (in stored order). A stable partition — each group keeps
    /// its stored relative order.
    public static func order(_ items: [TodoItem]) -> [TodoItem] {
        items.filter { !$0.done } + items.filter { $0.done }
    }

    /// The lower bound (in display-others space) of the dragged item's group:
    /// active items start at 0, completed items start right after the last active.
    private static func groupLowerBound(_ others: [TodoItem], group: Bool) -> Int {
        others.indices.first(where: { others[$0].done == group }) ?? (group ? others.count : 0)
    }

    /// Clamp a raw display-order insertion index (among the OTHER items, as the
    /// view's frame hit-test produces it) into the dragged item's own group, so
    /// an active item can't land among completed items and vice-versa.
    public static func clampedInsertion(_ items: [TodoItem], dragging id: UUID, rawInsertion: Int) -> Int {
        guard let dragged = items.first(where: { $0.id == id }) else { return rawInsertion }
        let others = order(items).filter { $0.id != id }
        let group = dragged.done
        let positions = others.indices.filter { others[$0].done == group }
        let lower = positions.first ?? (group ? others.count : 0)
        let upper = positions.last.map { $0 + 1 } ?? lower
        return min(max(rawInsertion, lower), upper)
    }

    /// New stored `items` after a whole-row drag. `rawInsertion` is the drop index
    /// among the OTHER items IN DISPLAY ORDER; it is clamped to the dragged item's
    /// group, then translated back to a MINIMAL stored-order move so every
    /// untouched item keeps its stored slot — only the dragged item relocates.
    public static func reordered(_ items: [TodoItem], dragging id: UUID, toDisplayInsertion rawInsertion: Int) -> [TodoItem] {
        guard let dragged = items.first(where: { $0.id == id }) else { return items }
        let group = dragged.done
        let clamped = clampedInsertion(items, dragging: id, rawInsertion: rawInsertion)

        // position within the dragged item's group (0…groupCount)
        let displayOthers = order(items).filter { $0.id != id }
        let lower = groupLowerBound(displayOthers, group: group)
        let withinGroup = clamped - lower

        // translate to a stored index: insert before the k-th same-group item in
        // STORED order (its relative order matches display), so nothing else moves.
        var storedOthers = items.filter { $0.id != id }
        let sameGroupOffsets = storedOthers.indices.filter { storedOthers[$0].done == group }
        let insertAt: Int
        if withinGroup < sameGroupOffsets.count {
            insertAt = sameGroupOffsets[withinGroup]
        } else if let last = sameGroupOffsets.last {
            insertAt = last + 1
        } else {
            // dragged is alone in its group — putting it back where it was lifted
            // from is a no-op (a one-item group can't reorder).
            insertAt = min(items.firstIndex(where: { $0.id == id }) ?? 0, storedOthers.count)
        }
        storedOthers.insert(dragged, at: min(insertAt, storedOthers.count))
        return storedOthers
    }
}

public extension TodoList {
    /// The list in display order (active first, completed last).
    var displayItems: [TodoItem] { TodoDisplay.order(items) }

    /// Reorders for a whole-row drag in the DISPLAYED list, clamped to the
    /// dragged item's group. `toDisplayInsertion` is the drop index among the
    /// OTHER displayed items. Persisted like every other mutation.
    mutating func reorderInDisplay(dragging id: UUID, toDisplayInsertion index: Int) {
        items = TodoDisplay.reordered(items, dragging: id, toDisplayInsertion: index)
    }
}
