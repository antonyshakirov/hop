import Foundation

/// Owns the tracker's projects, tasks and history and enforces the
/// single-active-task invariant: at most one interval is ever open
/// (`end == nil`) at a time, wherever in the tree that task sits.
public final class TrackerEngine: ObservableObject {
    @Published public private(set) var data: TrackerData
    /// Fired after every mutation — the persistence hook.
    public var onChange: (() -> Void)?

    private let now: () -> Date
    /// The calendar the day and week figures are cut by. Settable because the
    /// week's first day is the user's own setting and can change under a
    /// running app — the numbers simply recut from the next read on.
    public var calendar: Calendar

    public init(data: TrackerData = .empty,
                now: @escaping () -> Date = Date.init,
                calendar: Calendar = .current) {
        self.data = data
        self.now = now
        self.calendar = calendar
        normalizeStructure()
    }

    /// Repairs the stored shape so everything below can trust it: a task
    /// pointing at a project that is not there comes back to the top level,
    /// `rootOrder` ends up holding exactly the projects and the project-less
    /// tasks (once each), and every project's `taskOrder` holds exactly its own.
    /// Ordering survives wherever it was already sound; anything missing is
    /// appended in the arrays' own order. Runs on load — not a user mutation,
    /// so it never fires `onChange`.
    ///
    /// This is also the whole of the migration story in both directions. A file
    /// from the flat years has no projects and needs no conversion; a 1.3.x file
    /// that still nests tasks under projects simply loads as what it always was.
    private func normalizeStructure() {
        let projectIDs = Set(data.projects.map(\.id))
        for i in data.tasks.indices {
            if let owner = data.tasks[i].projectID, !projectIDs.contains(owner) {
                data.tasks[i].projectID = nil
            }
        }

        let topLevel = data.projects.map(\.id)
            + data.tasks.filter { $0.projectID == nil }.map(\.id)
        data.rootOrder = repaired(data.rootOrder, against: topLevel)

        for i in data.projects.indices {
            let own = data.tasks.filter { $0.projectID == data.projects[i].id }.map(\.id)
            data.projects[i].taskOrder = repaired(data.projects[i].taskOrder, against: own)
        }
    }

    /// Keeps the ids that are really there (in the order given), drops the rest,
    /// then appends whatever the reference has and the order does not.
    private func repaired(_ order: [UUID], against reference: [UUID]) -> [UUID] {
        let valid = Set(reference)
        var seen = Set<UUID>()
        var result = order.filter { valid.contains($0) && seen.insert($0).inserted }
        for id in reference where seen.insert(id).inserted { result.append(id) }
        return result
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

    // MARK: - Reading the tree

    /// The top level in display order: projects and project-less tasks, mixed.
    public var topLevel: [TrackerItem] {
        data.rootOrder.compactMap { id in
            if let project = data.projects.first(where: { $0.id == id }) {
                return .project(project)
            }
            if let task = data.tasks.first(where: { $0.id == id }) { return .task(task) }
            return nil
        }
    }

    /// A project's own tasks, in its stored order.
    public func tasks(in projectID: UUID) -> [TrackerTask] {
        guard let project = data.projects.first(where: { $0.id == projectID }) else { return [] }
        return project.taskOrder.compactMap { id in data.tasks.first { $0.id == id } }
    }

    /// Whether the running task is inside this project — a collapsed project
    /// still has to show that something under it is ticking.
    public func isTracking(projectID: UUID) -> Bool {
        guard let active = activeTaskID else { return false }
        return data.tasks.first { $0.id == active }?.projectID == projectID
    }

    // MARK: - Structure

    /// Appends a task, to a project when one is named and to the top level
    /// otherwise, and returns its id. An unknown project id lands the task at
    /// the top level rather than nowhere.
    @discardableResult
    public func addTask(name: String, projectID: UUID? = nil) -> UUID {
        let owner = projectID.flatMap { id in
            data.projects.contains { $0.id == id } ? id : nil
        }
        let task = TrackerTask(projectID: owner, name: name)
        data.tasks.append(task)
        if let owner, let index = data.projects.firstIndex(where: { $0.id == owner }) {
            data.projects[index].taskOrder.append(task.id)
        } else {
            data.rootOrder.append(task.id)
        }
        onChange?()
        return task.id
    }

    /// Appends a project to the top level and returns its id.
    @discardableResult
    public func addProject(name: String) -> UUID {
        let project = TrackerProject(name: name)
        data.projects.append(project)
        data.rootOrder.append(project.id)
        onChange?()
        return project.id
    }

    public func renameProject(_ id: UUID, to name: String) {
        guard let index = data.projects.firstIndex(where: { $0.id == id }) else { return }
        guard data.projects[index].name != name else { return }
        data.projects[index].name = name
        onChange?()
    }

    /// Folded or unfolded. Stored rather than kept in the view: a project the
    /// user folded should still be folded after a restart.
    public func setProjectExpanded(_ id: UUID, _ value: Bool) {
        guard let index = data.projects.firstIndex(where: { $0.id == id }) else { return }
        guard data.projects[index].isExpanded != value else { return }
        data.projects[index].isExpanded = value
        onChange?()
    }

    /// Deletes a project AND everything inside it — its tasks and all of their
    /// history (Anton, 2026-08-28). The view asks first, naming how many tasks
    /// and how many hours are about to go.
    public func deleteProject(_ id: UUID) {
        guard data.projects.contains(where: { $0.id == id }) else { return }
        for task in data.tasks where task.projectID == id {
            data.intervals.removeAll { $0.taskID == task.id }
            data.corrections.removeAll { $0.taskID == task.id }
        }
        data.tasks.removeAll { $0.projectID == id }
        data.projects.removeAll { $0.id == id }
        data.rootOrder.removeAll { $0 == id }
        onChange?()
    }

    public func renameTask(_ id: UUID, to name: String) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].name = name
        onChange?()
    }

    /// The task's comment, edited in the expanded card. A zero-delta write saves
    /// nothing, like every other mutator here.
    public func setNote(taskID id: UUID, to note: String) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard data.tasks[index].note != trimmed else { return }
        data.tasks[index].note = trimmed
        onChange?()
    }

    public func setImportant(taskID id: UUID, _ value: Bool) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        guard data.tasks[index].important != value else { return }
        data.tasks[index].important = value
        onChange?()
    }

    public func deleteTask(_ id: UUID) {
        // an unknown id removes nothing — skip the redundant save, mirroring the
        // other id-taking mutators
        let present = data.tasks.contains { $0.id == id }
            || data.rootOrder.contains(id)
            || data.intervals.contains { $0.taskID == id }
            || data.corrections.contains { $0.taskID == id }
        guard present else { return }
        // no separate "stop" step needed: dropping the task's own open
        // interval below already clears it from activeTaskID
        data.tasks.removeAll { $0.id == id }
        data.intervals.removeAll { $0.taskID == id }
        data.corrections.removeAll { $0.taskID == id }
        data.rootOrder.removeAll { $0 == id }
        for index in data.projects.indices {
            data.projects[index].taskOrder.removeAll { $0 == id }
        }
        onChange?()
    }

    // MARK: - Reordering (drag)

    /// Reorders the top level. `from` out of range is a no-op; `to` is clamped
    /// into the list after the item is lifted out.
    public func moveRootItem(from: Int, to: Int) {
        guard data.rootOrder.indices.contains(from) else { return }
        let id = data.rootOrder.remove(at: from)
        let clamped = max(0, min(to, data.rootOrder.count))
        data.rootOrder.insert(id, at: clamped)
        onChange?()
    }

    /// Reorders tasks inside one project, by the same rules.
    public func moveTaskInProject(_ projectID: UUID, from: Int, to: Int) {
        guard let index = data.projects.firstIndex(where: { $0.id == projectID }),
              data.projects[index].taskOrder.indices.contains(from) else { return }
        let id = data.projects[index].taskOrder.remove(at: from)
        let clamped = max(0, min(to, data.projects[index].taskOrder.count))
        data.projects[index].taskOrder.insert(id, at: clamped)
        onChange?()
    }

    /// Moves a task between levels: into a project, or out to the top level
    /// when `projectID` is nil. `index` is where it lands among its new
    /// siblings (appended when nil or out of range). History follows the task —
    /// intervals and corrections are keyed by task id and never touched here.
    /// An unknown task or an unknown destination project changes nothing.
    public func moveTask(_ id: UUID, toProject projectID: UUID?, at index: Int? = nil) {
        guard let taskIndex = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        if let projectID, !data.projects.contains(where: { $0.id == projectID }) { return }

        data.rootOrder.removeAll { $0 == id }
        for i in data.projects.indices { data.projects[i].taskOrder.removeAll { $0 == id } }

        data.tasks[taskIndex].projectID = projectID
        if let projectID, let i = data.projects.firstIndex(where: { $0.id == projectID }) {
            let clamped = max(0, min(index ?? data.projects[i].taskOrder.count,
                                     data.projects[i].taskOrder.count))
            data.projects[i].taskOrder.insert(id, at: clamped)
        } else {
            let clamped = max(0, min(index ?? data.rootOrder.count, data.rootOrder.count))
            data.rootOrder.insert(id, at: clamped)
        }
        onChange?()
    }

    // MARK: - Tracking

    public func start(taskID: UUID) {
        // An unknown id would open an orphan interval (active state with no task
        // behind it) — no-op instead, mirroring the other id-taking mutators.
        guard data.tasks.contains(where: { $0.id == taskID }) else { return }
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
        // Unknown id: refuse rather than record an orphan correction.
        guard data.tasks.contains(where: { $0.id == taskID }) else { return false }
        let target = max(0, seconds)
        // Diff against the raw (unclamped) sum, not the display-clamped today():
        // if the raw sum is already negative, diffing against 0 would under-shoot
        // and the edit could never reach a positive target in one correction.
        let delta = target - rawToday(taskID: taskID)
        // Setting the value it already holds is a no-op: an empty (zero-second)
        // correction would only bloat the file and fire a redundant save. This
        // also closes drag-left-at-zero writing a zero correction.
        guard delta != 0 else { return true }
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
        // Unknown id: refuse rather than record an orphan correction.
        guard data.tasks.contains(where: { $0.id == taskID }) else { return false }
        let target = max(0, seconds)
        let delta = target - rawTotal(taskID: taskID)
        // Zero delta = the total already equals the target: write no empty
        // correction and fire no redundant save (see `setToday`).
        guard delta != 0 else { return true }
        let startOfToday = calendar.startOfDay(for: now())
        data.corrections.append(TrackerCorrection(taskID: taskID, day: startOfToday, seconds: delta))
        onChange?()
        return true
    }

    /// Sets the figure the panel is currently showing, whichever period that
    /// is. The delta always lands as a correction dated today — today sits
    /// inside this week and inside all time, so one rule keeps every period
    /// consistent with the others.
    @discardableResult
    public func set(taskID: UUID, period: TrackerPeriod, to seconds: TimeInterval) -> Bool {
        switch period {
        case .today: return setToday(taskID: taskID, to: seconds)
        case .total: return setTotal(taskID: taskID, to: seconds)
        case .week: return setWeek(taskID: taskID, to: seconds)
        }
    }

    /// Sets the task's *this week* value, on `setToday`'s pattern: the delta is
    /// taken against the RAW weekly sum and dated today.
    @discardableResult
    public func setWeek(taskID: UUID, to seconds: TimeInterval) -> Bool {
        guard activeTaskID != taskID else { return false }
        guard data.tasks.contains(where: { $0.id == taskID }) else { return false }
        let delta = max(0, seconds) - rawWeek(taskID: taskID)
        guard delta != 0 else { return true }
        data.corrections.append(TrackerCorrection(
            taskID: taskID, day: calendar.startOfDay(for: now()), seconds: delta))
        onChange?()
        return true
    }

    // MARK: - Aggregates

    /// The task's figure for one period. Never negative.
    public func amount(taskID: UUID, period: TrackerPeriod) -> TimeInterval {
        switch period {
        case .today: return today(taskID: taskID)
        case .week: return week(taskID: taskID)
        case .total: return total(taskID: taskID)
        }
    }

    /// What a project's tasks add up to over a period — the number that made
    /// projects worth having back.
    public func amount(projectID: UUID, period: TrackerPeriod) -> TimeInterval {
        tasks(in: projectID).reduce(0) { $0 + amount(taskID: $1.id, period: period) }
    }

    /// Every closed interval in full, the open interval up to `now`, plus
    /// every correction ever recorded for the task. Never negative.
    public func total(taskID: UUID) -> TimeInterval {
        max(0, rawTotal(taskID: taskID))
    }

    /// Intervals clipped to this week so far, plus corrections dated within it.
    /// Which day the week starts on is the CALENDAR's business — the engine is
    /// handed one that already carries the user's setting. Never negative.
    public func week(taskID: UUID) -> TimeInterval {
        max(0, rawWeek(taskID: taskID))
    }

    private func rawWeek(taskID: UUID) -> TimeInterval {
        let nowDate = now()
        let start = weekStart(for: nowDate)
        let intervalsSum = data.intervals
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + clippedDuration(of: $1, from: start, to: nowDate) }
        let correctionsSum = data.corrections
            .filter { $0.taskID == taskID && $0.day >= start && $0.day <= nowDate }
            .reduce(0) { $0 + $1.seconds }
        return intervalsSum + correctionsSum
    }

    /// The start of the week `date` falls in, or its midnight if the calendar
    /// declines to say — a figure is better slightly short than absent.
    private func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
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
