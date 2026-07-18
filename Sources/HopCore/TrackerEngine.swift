import Foundation

/// Owns the tracker's projects/tasks/history and enforces the single-active-task
/// invariant: at most one interval is ever open (`end == nil`) at a time.
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
    }

    /// The task with an open interval, if any.
    public var activeTaskID: UUID? {
        data.intervals.first(where: { $0.end == nil })?.taskID
    }

    // MARK: - Structure

    @discardableResult
    public func addProject(name: String) -> UUID {
        let project = TrackerProject(name: name)
        data.projects.append(project)
        onChange?()
        return project.id
    }

    @discardableResult
    public func addTask(projectID: UUID, name: String) -> UUID {
        let task = TrackerTask(projectID: projectID, name: name)
        data.tasks.append(task)
        onChange?()
        return task.id
    }

    public func renameProject(_ id: UUID, to name: String) {
        guard let index = data.projects.firstIndex(where: { $0.id == id }) else { return }
        data.projects[index].name = name
        onChange?()
    }

    public func renameTask(_ id: UUID, to name: String) {
        guard let index = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[index].name = name
        onChange?()
    }

    public func deleteProject(_ id: UUID) {
        let taskIDs = Set(data.tasks.filter { $0.projectID == id }.map(\.id))
        data.projects.removeAll { $0.id == id }
        data.tasks.removeAll { taskIDs.contains($0.id) }
        data.intervals.removeAll { taskIDs.contains($0.taskID) }
        data.corrections.removeAll { taskIDs.contains($0.taskID) }
        onChange?()
    }

    public func deleteTask(_ id: UUID) {
        // no separate "stop" step needed: dropping the task's own open
        // interval below already clears it from activeTaskID
        data.tasks.removeAll { $0.id == id }
        data.intervals.removeAll { $0.taskID == id }
        data.corrections.removeAll { $0.taskID == id }
        onChange?()
    }

    public func setExpanded(projectID: UUID, _ expanded: Bool) {
        guard let index = data.projects.firstIndex(where: { $0.id == projectID }) else { return }
        data.projects[index].isExpanded = expanded
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
    /// Ignored (returns false) while the task is active.
    @discardableResult
    public func setToday(taskID: UUID, to seconds: TimeInterval) -> Bool {
        guard activeTaskID != taskID else { return false }
        let target = max(0, seconds)
        let delta = target - today(taskID: taskID)
        let startOfToday = calendar.startOfDay(for: now())
        data.corrections.append(TrackerCorrection(taskID: taskID, day: startOfToday, seconds: delta))
        onChange?()
        return true
    }

    // MARK: - Aggregates

    /// Every closed interval in full, the open interval up to `now`, plus
    /// every correction ever recorded for the task. Never negative.
    public func total(taskID: UUID) -> TimeInterval {
        let intervalsSum = data.intervals
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + duration(of: $1) }
        let correctionsSum = data.corrections
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + $1.seconds }
        return max(0, intervalsSum + correctionsSum)
    }

    /// Intervals clipped to `[startOfToday, now]` at query time — never
    /// physically split — plus corrections logged for today. Never negative.
    public func today(taskID: UUID) -> TimeInterval {
        let nowDate = now()
        let startOfToday = calendar.startOfDay(for: nowDate)
        let intervalsSum = data.intervals
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + clippedDuration(of: $1, from: startOfToday, to: nowDate) }
        let correctionsSum = data.corrections
            .filter { $0.taskID == taskID && calendar.isDate($0.day, inSameDayAs: startOfToday) }
            .reduce(0) { $0 + $1.seconds }
        return max(0, intervalsSum + correctionsSum)
    }

    /// Sums `total(taskID:)` (already clamped at 0) across the project's tasks.
    public func total(projectID: UUID) -> TimeInterval {
        data.tasks
            .filter { $0.projectID == projectID }
            .reduce(0) { $0 + total(taskID: $1.id) }
    }

    /// Sums `today(taskID:)` (already clamped at 0) across the project's tasks.
    public func today(projectID: UUID) -> TimeInterval {
        data.tasks
            .filter { $0.projectID == projectID }
            .reduce(0) { $0 + today(taskID: $1.id) }
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
