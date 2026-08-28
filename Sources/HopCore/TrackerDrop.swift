import Foundation

/// Where a dragged row lands in a list that now has two levels.
///
/// With a flat list an insertion was a number. With projects it is a number AND
/// a parent, and the two cannot be decided separately: the same pointer
/// position means "last task in this project" or "first task after it"
/// depending on what sits above it. Deciding both here, from measured row
/// positions alone, keeps the view free of that reasoning — and testable
/// without a pointer.
public enum TrackerDrop {
    /// One visible row, as the view measured it.
    public struct Row: Equatable, Sendable {
        public let id: UUID
        /// The project this row sits inside, nil for a row at the top level.
        public let parent: UUID?
        public let isProject: Bool
        /// Only meaningful for a project row: whether its tasks are on screen.
        public let isExpanded: Bool
        /// The row's vertical middle in the list's coordinate space.
        public let midY: Double

        public init(id: UUID, parent: UUID? = nil, isProject: Bool = false,
                    isExpanded: Bool = false, midY: Double) {
            self.id = id
            self.parent = parent
            self.isProject = isProject
            self.isExpanded = isExpanded
            self.midY = midY
        }
    }

    public struct Target: Equatable, Sendable {
        /// nil = the top level.
        public let parent: UUID?
        public let index: Int

        public init(parent: UUID?, index: Int) {
            self.parent = parent
            self.index = index
        }
    }

    /// The landing place for the row being dragged, at pointer height `y`.
    ///
    /// A project only ever lands at the top level — projects do not nest, and a
    /// project dropped into itself would be a list that contains itself.
    /// A task takes the level of the row above the pointer: inside a project
    /// when that row is a task of one or an unfolded project's own header,
    /// otherwise at the top level. Which means a task leaves a project by being
    /// dropped above it or below a row that belongs to nobody — a folded
    /// project included.
    public static func target(rows: [Row], dragging id: UUID, isProject: Bool,
                              at y: Double) -> Target {
        // the dragged row travels with the pointer, and so do a project's own
        // tasks — neither can be a landmark for the drop
        let others = rows.filter { $0.id != id && $0.parent != id }

        let parent: UUID?
        if isProject {
            parent = nil
        } else if let above = others.last(where: { $0.midY < y }) {
            parent = above.isProject ? (above.isExpanded ? above.id : nil) : above.parent
        } else {
            parent = nil
        }

        let index = others.filter { $0.parent == parent && $0.midY < y }.count
        return Target(parent: parent, index: index)
    }
}
