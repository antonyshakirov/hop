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
}
