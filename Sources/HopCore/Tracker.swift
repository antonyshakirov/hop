import Foundation

/// A named group of tasks. Projects were dissolved in 1.4.0 because they made
/// a short list feel like a filing cabinet, and brought back in 1.9.0 with
/// week totals to answer the question that made them worth having: where did
/// this week go (Anton, 2026-08-28). A file written in between simply has none.
public struct TrackerProject: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var isExpanded: Bool
    /// The order of the project's own tasks — the same contract `rootOrder`
    /// holds for the top level: exactly the ids of the tasks whose `projectID`
    /// is this project, no duplicates, repaired by the engine on load.
    public var taskOrder: [UUID]

    public init(id: UUID = UUID(), name: String, isExpanded: Bool = true,
                taskOrder: [UUID] = []) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.taskOrder = taskOrder
    }

    private enum CodingKeys: String, CodingKey { case id, name, isExpanded, taskOrder }

    /// Tolerant like the task's: a project written before `taskOrder` existed
    /// (every 1.3.x file) carries no such key, and a synthesised decoder would
    /// reject the whole file over it. The engine derives the order instead.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        taskOrder = try c.decodeIfPresent([UUID].self, forKey: .taskOrder) ?? []
    }
}

/// A trackable unit of work. `projectID` is the single source of BELONGING —
/// nil for a task sitting at the top level, a project's id for one inside it.
/// The orders (`rootOrder`, `TrackerProject.taskOrder`) only ever say where
/// among its siblings a task sits, never whose it is.
public struct TrackerTask: Codable, Equatable, Identifiable {
    public let id: UUID
    public var projectID: UUID?
    public var name: String
    /// Free-form comment shown in the expanded card.
    public var note: String
    /// The importance mark. Whether it also sorts the list is a setting.
    public var important: Bool

    public init(id: UUID = UUID(), projectID: UUID? = nil, name: String,
                note: String = "", important: Bool = false) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.note = note
        self.important = important
    }

    private enum CodingKeys: String, CodingKey { case id, projectID, name, note, important }

    /// Hand-written rather than synthesised: a tracker.json from before these
    /// fields existed carries neither key, and a synthesised decoder would reject
    /// it outright — which would move the user's whole task list aside as a .bak.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        important = try container.decodeIfPresent(Bool.self, forKey: .important) ?? false
    }
}

/// The stretch of time a figure covers. The panel shows one of them at a time,
/// chosen in the tracker's own header, because three numbers per row in a
/// 360-point panel is a spreadsheet rather than a list (Anton, 2026-08-28).
public enum TrackerPeriod: String, CaseIterable, Sendable {
    case today
    case week
    case total
}

/// One line of the top level: a project, or a task belonging to none. The view
/// walks `rootOrder` through this rather than testing ids against two arrays.
public enum TrackerItem: Equatable, Identifiable {
    case project(TrackerProject)
    case task(TrackerTask)

    public var id: UUID {
        switch self {
        case .project(let project): return project.id
        case .task(let task): return task.id
        }
    }
}

/// A single tracked span of time on a task. `end` is nil while the interval
/// is still open (the timer is running now).
///
/// It has an `id` because a session is now something a person edits: the card
/// lists every stretch of time the task collected and lets any of them be
/// changed, removed or added by hand (Anton, 2026-08-28). A file written before
/// ids existed gets fresh ones on load — they are stable from the first save
/// after that, which is all editing needs.
public struct TrackerInterval: Codable, Equatable, Identifiable {
    public let id: UUID
    public let taskID: UUID
    public var start: Date
    public var end: Date?
    /// False while the interval belongs to the RUN the task is in the middle of
    /// — the stretch of work started by play and ended by the ✓ (Anton,
    /// 2026-08-29). Pausing leaves it false, so play/pause/play is one run made
    /// of several intervals; the ✓ flips them all to true and the run is over.
    /// Defaults to true so a file written before runs existed reads as what it
    /// is: history, already filed.
    public var committed: Bool

    public init(id: UUID = UUID(), taskID: UUID, start: Date, end: Date? = nil,
                committed: Bool = true) {
        self.id = id
        self.taskID = taskID
        self.start = start
        self.end = end
        self.committed = committed
    }

    private enum CodingKeys: String, CodingKey { case id, taskID, start, end, committed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        taskID = try c.decode(UUID.self, forKey: .taskID)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        committed = try c.decodeIfPresent(Bool.self, forKey: .committed) ?? true
    }
}

/// A manual adjustment to a task's tracked time on a given day, applied on
/// top of whatever the recorded intervals sum to (e.g. to fix a forgotten
/// stop). `seconds` is signed: positive adds time, negative removes it.
public struct TrackerCorrection: Codable, Equatable, Identifiable {
    /// Same reason as the interval's: a correction shows up in the task's
    /// history and can be edited or thrown away from there.
    public let id: UUID
    public let taskID: UUID
    /// INVARIANT: every correction the engine writes is dated the START OF DAY
    /// (midnight) in the engine's calendar — `setToday`/`setTotal` use
    /// `calendar.startOfDay(for:)`. Today-scoping compares with
    /// `isDate(_:inSameDayAs:)`, so a stray non-midnight value from a hand-edited
    /// or legacy file still matches its day, but engine-authored records are
    /// always normalized to midnight.
    public let day: Date
    public var seconds: TimeInterval

    public init(id: UUID = UUID(), taskID: UUID, day: Date, seconds: TimeInterval) {
        self.id = id
        self.taskID = taskID
        self.day = day
        self.seconds = seconds
    }

    private enum CodingKeys: String, CodingKey { case id, taskID, day, seconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        taskID = try c.decode(UUID.self, forKey: .taskID)
        day = try c.decode(Date.self, forKey: .day)
        seconds = try c.decode(TimeInterval.self, forKey: .seconds)
    }
}

/// One line of a task's history: a tracked session, or a by-hand adjustment.
/// The two are shown together because together they ARE the task's total, and
/// a list that quietly omitted half of it would not add up on screen.
public struct TrackerHistoryEntry: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A stretch that was actually tracked. `running` is the open one;
        /// `filed` is false while the stretch still belongs to the run in
        /// progress, so the card can show which lines the ✓ is about to close.
        case session(start: Date, running: Bool, filed: Bool)
        /// A correction, dated to its day.
        case adjustment(day: Date)
    }

    public let id: UUID
    public let kind: Kind
    /// Signed: an adjustment can take time away.
    public let seconds: TimeInterval

    public init(id: UUID, kind: Kind, seconds: TimeInterval) {
        self.id = id
        self.kind = kind
        self.seconds = seconds
    }

    public var isRunning: Bool {
        if case .session(_, let running, _) = kind { return running }
        return false
    }

    /// True while this line is part of the run the task is in the middle of —
    /// the ✓ is what turns it into plain history.
    public var isOpenRun: Bool {
        if case .session(_, _, let filed) = kind { return !filed }
        return false
    }

    /// When the line happened, for sorting and for showing a date.
    public var moment: Date {
        switch kind {
        case .session(let start, _, _): return start
        case .adjustment(let day): return day
        }
    }
}

/// The full persisted state of the tracker: projects, tasks, and the recorded
/// intervals and corrections against those tasks.
///
/// `rootOrder` is the ordered list of what sits at the TOP LEVEL — project ids
/// and the ids of tasks belonging to no project, mixed, because that is how the
/// list reads on screen. It holds each of them exactly once;
/// `TrackerEngine.init` repairs it, along with every project's `taskOrder`.
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
