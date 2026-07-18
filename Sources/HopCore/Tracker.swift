import Foundation

/// A top-level bucket of work in the tracker, e.g. "Hop" or "Client X".
public struct TrackerProject: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var isExpanded: Bool

    public init(id: UUID = UUID(), name: String, isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
    }
}

/// A trackable unit of work nested under a project.
public struct TrackerTask: Codable, Equatable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public var name: String

    public init(id: UUID = UUID(), projectID: UUID, name: String) {
        self.id = id
        self.projectID = projectID
        self.name = name
    }
}

/// A single tracked span of time on a task. `end` is nil while the interval
/// is still open (the timer is running now).
public struct TrackerInterval: Codable, Equatable {
    public let taskID: UUID
    public let start: Date
    public var end: Date?

    public init(taskID: UUID, start: Date, end: Date? = nil) {
        self.taskID = taskID
        self.start = start
        self.end = end
    }
}

/// A manual adjustment to a task's tracked time on a given day, applied on
/// top of whatever the recorded intervals sum to (e.g. to fix a forgotten
/// stop). `seconds` is signed: positive adds time, negative removes it.
public struct TrackerCorrection: Codable, Equatable {
    public let taskID: UUID
    public let day: Date
    public let seconds: TimeInterval

    public init(taskID: UUID, day: Date, seconds: TimeInterval) {
        self.taskID = taskID
        self.day = day
        self.seconds = seconds
    }
}

/// The full persisted state of the tracker: projects, their tasks, and the
/// recorded intervals and corrections against those tasks.
public struct TrackerData: Codable, Equatable {
    public var projects: [TrackerProject]
    public var tasks: [TrackerTask]
    public var intervals: [TrackerInterval]
    public var corrections: [TrackerCorrection]

    public static let empty = TrackerData(projects: [], tasks: [], intervals: [], corrections: [])
}
