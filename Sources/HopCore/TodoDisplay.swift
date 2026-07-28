import Foundation

/// Pure display-ordering and drag-clamping for the to-do list. Neither completing
/// an item nor marking it important ever touches the stored order
/// (`TodoList.items`): a completed item merely sinks to the bottom for DISPLAY
/// and an important one merely rises to the top, so unchecking or unmarking
/// returns it to its slot for free. A whole-row drag reorders WITHIN a group and
/// never crosses a group boundary.
public enum TodoDisplay {

    /// Display groups, in order: important actives (only while the setting is on),
    /// ordinary actives, then everything completed.
    private static func group(_ item: TodoItem, importantFirst: Bool) -> Int {
        if item.done { return 2 }
        return (importantFirst && item.important) ? 0 : 1
    }

    /// Items in display order — a stable partition, so each group keeps its
    /// stored relative order.
    public static func order(_ items: [TodoItem], importantFirst: Bool = false) -> [TodoItem] {
        (0...2).flatMap { g in items.filter { group($0, importantFirst: importantFirst) == g } }
    }

    /// Clamp a raw display-order insertion index (among the OTHER items, as the
    /// view's frame hit-test produces it) into the dragged item's own group, so a
    /// row can never land in a group it does not belong to.
    public static func clampedInsertion(_ items: [TodoItem], dragging id: UUID,
                                        rawInsertion: Int,
                                        importantFirst: Bool = false) -> Int {
        guard let dragged = items.first(where: { $0.id == id }) else { return rawInsertion }
        let others = order(items, importantFirst: importantFirst).filter { $0.id != id }
        let draggedGroup = group(dragged, importantFirst: importantFirst)
        let positions = others.indices
            .filter { group(others[$0], importantFirst: importantFirst) == draggedGroup }
        let lower = positions.first ?? others.count
        let upper = positions.last.map { $0 + 1 } ?? lower
        return min(max(rawInsertion, lower), upper)
    }

    /// New stored `items` after a whole-row drag. `rawInsertion` is the drop index
    /// among the OTHER items IN DISPLAY ORDER; it is clamped to the dragged item's
    /// group, then translated back to a MINIMAL stored-order move so every
    /// untouched item keeps its stored slot — only the dragged item relocates.
    public static func reordered(_ items: [TodoItem], dragging id: UUID,
                                 toDisplayInsertion rawInsertion: Int,
                                 importantFirst: Bool = false) -> [TodoItem] {
        guard let dragged = items.first(where: { $0.id == id }) else { return items }
        let draggedGroup = group(dragged, importantFirst: importantFirst)
        let clamped = clampedInsertion(items, dragging: id, rawInsertion: rawInsertion,
                                       importantFirst: importantFirst)

        // position within the dragged item's group (0…groupCount)
        let displayOthers = order(items, importantFirst: importantFirst).filter { $0.id != id }
        let lower = displayOthers.indices
            .first(where: { group(displayOthers[$0], importantFirst: importantFirst) == draggedGroup })
            ?? displayOthers.count
        let withinGroup = clamped - lower

        // translate to a stored index: insert before the k-th same-group item in
        // STORED order (its relative order matches display), so nothing else moves.
        var storedOthers = items.filter { $0.id != id }
        let sameGroupOffsets = storedOthers.indices
            .filter { group(storedOthers[$0], importantFirst: importantFirst) == draggedGroup }
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

    /// The list in display order, optionally floating important items to the top.
    func displayItems(importantFirst: Bool) -> [TodoItem] {
        TodoDisplay.order(items, importantFirst: importantFirst)
    }

    /// Reorders for a whole-row drag in the DISPLAYED list, clamped to the
    /// dragged item's group. `toDisplayInsertion` is the drop index among the
    /// OTHER displayed items. Persisted like every other mutation.
    mutating func reorderInDisplay(dragging id: UUID, toDisplayInsertion index: Int,
                                   importantFirst: Bool = false) {
        items = TodoDisplay.reordered(items, dragging: id, toDisplayInsertion: index,
                                      importantFirst: importantFirst)
    }
}
