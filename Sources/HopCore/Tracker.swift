import Foundation

/// LEGACY. The tracker no longer has projects — the model still decodes this
/// type so an old `tracker.json` written with projects loads, but the engine
/// flattens every project away on init (its tasks become root tasks) and never
/// writes a non-empty `projects` array again. Kept only for backward decode.
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

/// A trackable unit of work. The tracker is a flat list now, so every live task
/// is a ROOT task with `projectID == nil`. The optional stays for backward
/// decode: an old file nests tasks under a project id, and the engine detaches
/// them (sets `projectID = nil`) when it flattens on load.
public struct TrackerTask: Codable, Equatable, Identifiable {
    public let id: UUID
    public var projectID: UUID?
    public var name: String

    public init(id: UUID = UUID(), projectID: UUID? = nil, name: String) {
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

/// The full persisted state of the tracker: a flat list of tasks and the
/// recorded intervals and corrections against them. `projects` is legacy: it is
/// still decoded so old files load, but the engine flattens it to empty on init.
///
/// `rootOrder` is the ordered list of task ids — the single source of the flat
/// list's order. It holds exactly the ids of every task, with no duplicates;
/// `TrackerEngine.init` flattens legacy projects, then normalizes/repairs it.
public struct TrackerData: Codable, Equatable {
    public var projects: [TrackerProject]
    public var tasks: [TrackerTask]
    public var intervals: [TrackerInterval]
    public var corrections: [TrackerCorrection]
    public var rootOrder: [UUID]

    public init(projects: [TrackerProject],
                tasks: [TrackerTask],
                intervals: [TrackerInterval],
                corrections: [TrackerCorrection],
                rootOrder: [UUID] = []) {
        self.projects = projects
        self.tasks = tasks
        self.intervals = intervals
        self.corrections = corrections
        self.rootOrder = rootOrder
    }

    public static let empty = TrackerData(projects: [], tasks: [], intervals: [], corrections: [])
}

extension TrackerData {
    /// Tolerant decode: every array field defaults to empty when absent, so an
    /// old `tracker.json` written before `rootOrder` existed still loads (the
    /// engine derives the order on init). Unknown keys are ignored as before.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([TrackerProject].self, forKey: .projects) ?? []
        tasks = try c.decodeIfPresent([TrackerTask].self, forKey: .tasks) ?? []
        intervals = try c.decodeIfPresent([TrackerInterval].self, forKey: .intervals) ?? []
        corrections = try c.decodeIfPresent([TrackerCorrection].self, forKey: .corrections) ?? []
        rootOrder = try c.decodeIfPresent([UUID].self, forKey: .rootOrder) ?? []
    }
}
