import Foundation

struct PanelSpaceHeightCache {
    private var heights: [UUID: CGFloat] = [:]
    private var expandedModules: [UUID: Set<String>] = [:]
    private var revisions: [UUID: Int] = [:]

    func height(for space: UUID) -> CGFloat? { heights[space] }
    func revision(for space: UUID) -> Int { revisions[space, default: 0] }

    mutating func store(_ height: CGFloat, for space: UUID, revision: Int) {
        guard revision == self.revision(for: space),
              expandedModules[space]?.isEmpty != false,
              heights[space] != height else { return }
        heights[space] = height
    }

    mutating func setExpanded(_ expanded: Bool, module: String, in space: UUID) {
        var modules = expandedModules[space] ?? []
        let changed: Bool
        if expanded {
            changed = modules.insert(module).inserted
        } else {
            changed = modules.remove(module) != nil
        }
        guard changed else { return }
        if modules.isEmpty { expandedModules.removeValue(forKey: space) }
        else { expandedModules[space] = modules }
        heights.removeValue(forKey: space)
        revisions[space, default: 0] += 1
    }

    mutating func clear() {
        let spaces = Set(heights.keys).union(expandedModules.keys).union(revisions.keys)
        heights.removeAll()
        for space in spaces { revisions[space, default: 0] += 1 }
    }
}
