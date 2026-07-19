import Foundation

/// Owns the tracker's flat task list and history and enforces the
/// single-active-task invariant: at most one interval is ever open
/// (`end == nil`) at a time. Projects are gone from the model's surface — an
/// old file that still has them is flattened away on init.
public final class TrackerEngine: ObservableObject {
    @Published public private(set) var data: TrackerData
    /// Fired after every mutation — the persistence hook.
    public var onChange: (() -> Void)?

    private let now: () -> Date
    private let calendar: Calendar

    public init(data: TrackerData = .empty,
                now: @escaping () -> Date = Date.init,
                calendar: Calendar = .current) {
        self.data = data
        self.now = now
        self.calendar = calendar
        flattenProjects()
        normalizeRootOrder()
    }

    /// One-shot migration: dissolves every legacy project into the flat task
    /// list. Each task keeps its identity and all history; a project's tasks
    /// expand IN PLACE where the project sat in `rootOrder` (their internal
    /// order preserved), root tasks stay put, and the `projects` array empties.
    /// A file with no `rootOrder` derives the order from the projects' array
    /// order (each expanded to its tasks) followed by any root tasks. Idempotent
    /// once flat — a no-op when there is nothing left to flatten. Runs once on
    /// load; not a user mutation, so it never fires `onChange`.
    private func flattenProjects() {
        guard !data.projects.isEmpty || data.tasks.contains(where: { $0.projectID != nil }) else { return }

        let projectIDs = Set(data.projects.map(\.id))
        func tasks(of projectID: UUID) -> [UUID] {
            data.tasks.filter { $0.projectID == projectID }.map(\.id)
        }

        var flat: [UUID] = []
        var seen = Set<UUID>()
        // 1. Follow the existing rootOrder, expanding a project's tasks in place.
        for id in data.rootOrder {
            if projectIDs.contains(id) {
                for tid in tasks(of: id) where seen.insert(tid).inserted { flat.append(tid) }
            } else if seen.insert(id).inserted {
                flat.append(id)   // a root task id (filtered to real tasks below)
            }
        }
        // 2. Append any project not covered by rootOrder (array order), its tasks.
        for project in data.projects {
            for tid in tasks(of: project.id) where seen.insert(tid).inserted { flat.append(tid) }
        }
        // 3. Append any leftover root task not yet placed.
        for task in data.tasks where task.projectID == nil && seen.insert(task.id).inserted {
            flat.append(task.id)
        }

        // Keep only ids that are real tasks (drop any stray non-task rootOrder id).
        let taskIDs = Set(data.tasks.map(\.id))
        data.rootOrder = flat.filter { taskIDs.contains($0) }

        // Detach every task from its (now dissolved) project and drop the projects.
        for i in data.tasks.indices { data.tasks[i].projectID = nil }
        data.projects.removeAll()
    }

    /// Repairs `rootOrder` so it holds exactly every task id, no duplicates:
    /// keep the ids already listed (in order), drop stale ones, then append any
    /// missing ids in the tasks' array order. Runs once on load after
    /// `flattenProjects`; not a user mutation, so it never fires `onChange`.
    private func normalizeRootOrder() {
        let taskIDs = data.tasks.map(\.id)
        let valid = Set(taskIDs)

        var seen = Set<UUID>()
        var repaired = data.rootOrder.filter { valid.contains($0) && seen.insert($0).inserted }
        for id in taskIDs where seen.insert(id).inserted { repaired.append(id) }

        data.rootOrder = repaired
    }

    /// The task with an open interval, if any.
    public var activeTaskID: UUID? {
        data.intervals.first(where: { $0.end == nil })?.taskID
    }

    /// The start of the currently open interval, if a task is active — lets the
    /// view flag a run that has been going for over 8 hours.
    public var activeIntervalStart: Date? {
        data.intervals.first(where: { $0.end == nil })?.start
    }

    // MARK: - Structure

    /// Appends a task to the flat list (and to `rootOrder`), returning its id.
    @discardableResult
    public func addTask(name: String) -> UUID {
        let task = TrackerTask(name: name)
        data.tasks.append(task)
        data.rootOrder.append(task.id)
        onChange?()
        return task.id
    }

    public func renameTask(_ id: UUID, to name: String) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].name = name
        onChange?()
    }

    public func deleteTask(_ id: UUID) {
        // no separate "stop" step needed: dropping the task's own open
        // interval below already clears it from activeTaskID
        data.tasks.removeAll { $0.id == id }
        data.intervals.removeAll { $0.taskID == id }
        data.corrections.removeAll { $0.taskID == id }
        data.rootOrder.removeAll { $0 == id }
        onChange?()
    }

    // MARK: - Reordering (drag)

    /// Reorders the flat task list. `from` out of range is a no-op; `to` is
    /// clamped into the list after the item is lifted out.
    public func moveRootItem(from: Int, to: Int) {
        guard data.rootOrder.indices.contains(from) else { return }
        let id = data.rootOrder.remove(at: from)
        let clamped = max(0, min(to, data.rootOrder.count))
        data.rootOrder.insert(id, at: clamped)
        onChange?()
    }

    // MARK: - Tracking

    public func start(taskID: UUID) {
        guard activeTaskID != taskID else { return }
        closeActiveInterval()
        data.intervals.append(TrackerInterval(taskID: taskID, start: now()))
        onChange?()
    }

    public func stopActive() {
        guard activeTaskID != nil else { return }
        closeActiveInterval()
        onChange?()
    }

    private func closeActiveInterval() {
        guard let index = data.intervals.firstIndex(where: { $0.end == nil }) else { return }
        data.intervals[index].end = now()
    }

    // MARK: - Manual edits

    /// Sets the task's *today* value; the delta lands as a correction dated today.
    /// Ignored (returns false) while the task is active. Kept for the menu-bar
    /// "today" figure — the panel edits the total (see `setTotal`).
    @discardableResult
    public func setToday(taskID: UUID, to seconds: TimeInterval) -> Bool {
        guard activeTaskID != taskID else { return false }
        let target = max(0, seconds)
        // Diff against the raw (unclamped) sum, not the display-clamped today():
        // if the raw sum is already negative, diffing against 0 would under-shoot
        // and the edit could never reach a positive target in one correction.
        let delta = target - rawToday(taskID: taskID)
        let startOfToday = calendar.startOfDay(for: now())
        data.corrections.append(TrackerCorrection(taskID: taskID, day: startOfToday, seconds: delta))
        onChange?()
        return true
    }

    /// Sets the task's all-time *total*; the delta lands as a correction dated
    /// today. Ignored (returns false) while the task is active. Mirrors
    /// `setToday`'s raw-baseline lesson: the delta diffs against the RAW
    /// (unclamped) total, so a heavily over-corrected task can still be brought
    /// back to a positive target in one edit. The target is clamped ≥ 0.
    @discardableResult
    public func setTotal(taskID: UUID, to seconds: TimeInterval) -> Bool {
        guard activeTaskID != taskID else { return false }
        let target = max(0, seconds)
        let delta = target - rawTotal(taskID: taskID)
        let startOfToday = calendar.startOfDay(for: now())
        data.corrections.append(TrackerCorrection(taskID: taskID, day: startOfToday, seconds: delta))
        onChange?()
        return true
    }

    // MARK: - Aggregates

    /// Every closed interval in full, the open interval up to `now`, plus
    /// every correction ever recorded for the task. Never negative.
    public func total(taskID: UUID) -> TimeInterval {
        max(0, rawTotal(taskID: taskID))
    }

    /// Same sum as `total(taskID:)`, without the display clamp — lets callers
    /// that need a diff (e.g. `setTotal`) work against the true underlying value
    /// even when it has gone negative.
    private func rawTotal(taskID: UUID) -> TimeInterval {
        let intervalsSum = data.intervals
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + duration(of: $1) }
        let correctionsSum = data.corrections
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + $1.seconds }
        return intervalsSum + correctionsSum
    }

    /// Intervals clipped to `[startOfToday, now]` at query time — never
    /// physically split — plus corrections logged for today. Never negative.
    /// Kept for the menu-bar figure; the panel shows the total.
    public func today(taskID: UUID) -> TimeInterval {
        max(0, rawToday(taskID: taskID))
    }

    /// Same sum as `today(taskID:)`, without the display clamp — lets callers
    /// that need to compute a diff (e.g. `setToday`) work against the true
    /// underlying value even when it has gone negative.
    private func rawToday(taskID: UUID) -> TimeInterval {
        let nowDate = now()
        let startOfToday = calendar.startOfDay(for: nowDate)
        let intervalsSum = data.intervals
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + clippedDuration(of: $1, from: startOfToday, to: nowDate) }
        let correctionsSum = data.corrections
            .filter { $0.taskID == taskID && calendar.isDate($0.day, inSameDayAs: startOfToday) }
            .reduce(0) { $0 + $1.seconds }
        return intervalsSum + correctionsSum
    }

    private func duration(of interval: TrackerInterval) -> TimeInterval {
        let end = interval.end ?? now()
        return max(0, end.timeIntervalSince(interval.start))
    }

    private func clippedDuration(of interval: TrackerInterval, from rangeStart: Date, to rangeEnd: Date) -> TimeInterval {
        let end = interval.end ?? now()
        let clippedStart = max(interval.start, rangeStart)
        let clippedEnd = min(end, rangeEnd)
        return max(0, clippedEnd.timeIntervalSince(clippedStart))
    }
}
