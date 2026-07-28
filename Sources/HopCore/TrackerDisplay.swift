import Foundation

/// The tracker's display ordering. It has no completed pile, so importance is the
/// only grouping — and, like the to-do list, it is display-only: the stored order
/// (`TrackerData.rootOrder`) is never mutated by marking a task important, so
/// unmarking returns it to its own slot.
public enum TrackerDisplay {

    /// Tasks in display order. With the setting off the list is returned
    /// untouched, which is the ordering the tracker has always had.
    public static func order(_ tasks: [TrackerTask], importantFirst: Bool) -> [TrackerTask] {
        guard importantFirst else { return tasks }
        return tasks.filter(\.important) + tasks.filter { !$0.important }
    }

    /// Clamp a raw display-order insertion index into the dragged task's own
    /// group. With the setting off there are no groups, so nothing is clamped.
    public static func clampedInsertion(_ tasks: [TrackerTask], dragging id: UUID,
                                        rawInsertion: Int, importantFirst: Bool) -> Int {
        guard importantFirst, let dragged = tasks.first(where: { $0.id == id }) else {
            return rawInsertion
        }
        let others = order(tasks, importantFirst: true).filter { $0.id != id }
        let positions = others.indices.filter { others[$0].important == dragged.important }
        let lower = positions.first ?? others.count
        let upper = positions.last.map { $0 + 1 } ?? lower
        return min(max(rawInsertion, lower), upper)
    }
}
