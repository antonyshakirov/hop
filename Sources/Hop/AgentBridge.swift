import AppKit
import HopCore
import os

/// Lets something outside the app — the user's own AI agent, a script, a
/// Shortcut — both READ what Hop is doing and TELL it what to do, through two
/// plain JSON files next to the app's other data:
///
///   agent-commands.json   written by the agent, performed and then emptied
///   agent-state.json      written by Hop, a snapshot of what is running
///
/// Files rather than a URL scheme or a CLI because that is the surface an agent
/// already has: it can read and write files without being taught anything, and
/// the same mechanism serves a hand edit and a machine on the other end of a
/// synced folder.
@MainActor
final class AgentBridge {
    static let commandsFileName = "agent-commands.json"
    static let stateFileName = "agent-state.json"

    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "AgentBridge")

    private let directory: URL
    private weak var model: AppModel?
    private var commandWatcher: FileWatcher?
    private var stateTicker: Timer?

    var commandsURL: URL { directory.appendingPathComponent(Self.commandsFileName) }
    var stateURL: URL { directory.appendingPathComponent(Self.stateFileName) }

    init(directory: URL) {
        self.directory = directory
    }

    /// Starts watching for commands and publishing state. A snapshot render is
    /// skipped outright: it must not touch real user data.
    func start(model: AppModel) {
        guard !Snapshot.active else { return }
        self.model = model
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: commandsURL.path) {
            // create it empty so an agent can find the path before ever writing,
            // and so the watcher has a descriptor to hold from the start
            write(Data("{\"commands\": []}\n".utf8), to: commandsURL)
        }
        publishState()

        let watcher = FileWatcher(url: commandsURL) { [weak self] in self?.runCommands() }
        watcher.start()
        commandWatcher = watcher

        // The state snapshot is a courtesy, not a live feed: a 5s refresh keeps
        // "what is running right now" honest without writing a file every tick.
        let ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in self.publishState() }
        }
        ticker.tolerance = 2
        stateTicker = ticker

        // Catch anything written while Hop was not running.
        runCommands()
    }

    // MARK: - Commands

    private func runCommands() {
        guard let model else { return }
        guard let data = try? Data(contentsOf: commandsURL), !data.isEmpty else { return }
        let commands = AgentCommandParser.parse(data)
        guard !commands.isEmpty else {
            // Nothing usable: leave the file alone rather than silently eating
            // whatever the agent wrote, so a malformed file can be seen and fixed.
            return
        }
        for command in commands { perform(command, on: model) }
        Self.log.info("agent: performed \(commands.count, privacy: .public) command(s)")
        // Emptying the file IS the acknowledgement — an agent can watch for it.
        write(Data("{\"commands\": []}\n".utf8), to: commandsURL)
        publishState()
    }

    /// Performs one command from wherever it came — the file or a `hop://` link.
    func perform(_ command: AgentCommand) {
        guard let model else { return }
        perform(command, on: model)
        publishState()
    }

    private func perform(_ command: AgentCommand, on model: AppModel) {
        switch command {
        case .timerStart(let seconds):
            model.engine.setStopwatch(false)
            model.engine.reset()
            model.engine.setDuration(TimeInterval(seconds))
            model.engine.start()
        case .timerPause:
            model.engine.pause()
        case .timerReset:
            model.engine.reset()
        case .stopwatchStart:
            model.engine.setStopwatch(true)
            model.engine.start()
        case .stopwatchStop:
            model.engine.pause()
        case .trackerStart(let name):
            // Match an existing task by name before inventing one, so "track
            // design" twice does not leave two tasks called design.
            let existing = model.tracker.engine.data.tasks.first {
                $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            let id = existing?.id ?? model.tracker.engine.addTask(name: name)
            model.tracker.engine.start(taskID: id)
        case .trackerStop:
            model.tracker.engine.stopActive()
        case .todoAdd(let draft):
            guard let id = model.todos.add(text: draft.text) else { return }
            if !draft.note.isEmpty { model.todos.setNote(id, to: draft.note) }
            if draft.important { model.todos.setImportant(id, true) }
            if let at = draft.remindAt {
                model.todos.setReminder(id, at: at, repeatDays: draft.repeatDays)
            }
        case .todoComplete(let text):
            let match = model.todos.list.items.first {
                !$0.done && $0.text.compare(text, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if let match { model.todos.toggle(match.id) }
        case .keepAwake(let on):
            if on {
                // the indefinite option — an agent asking to keep the Mac awake
                // has no way to mean "for 30 minutes" unless it says so
                if let indefinite = KeepAwakeController.options.first(where: { $0.seconds == nil }) {
                    model.keepAwake.activate(indefinite)
                }
            } else {
                model.keepAwake.deactivate()
            }
        }
    }

    // MARK: - State

    /// A snapshot of what Hop is doing, for an agent to read before it decides
    /// anything. Written whole each time; never partially updated.
    private func publishState() {
        guard let model else { return }
        let timer = model.engine
        var state: [String: Any] = [
            "version": 1,
            "timer": [
                "mode": timer.isStopwatch ? "stopwatch" : "countdown",
                "state": "\(timer.state)",
                "remainingSeconds": Int(timer.remaining),
                "durationSeconds": Int(timer.duration),
            ],
            "keepAwake": model.keepAwake.isActive,
        ]
        let engine = model.tracker.engine
        if let activeID = engine.activeTaskID,
           let task = engine.data.tasks.first(where: { $0.id == activeID }) {
            state["tracking"] = ["task": task.name, "todaySeconds": Int(engine.today(taskID: activeID))]
        }
        state["todos"] = model.todos.list.items.map { item -> [String: Any] in
            var out: [String: Any] = ["id": item.id.uuidString, "text": item.text, "done": item.done]
            if !item.note.isEmpty { out["note"] = item.note }
            if item.important { out["important"] = true }
            if let at = item.remindAt { out["remindAt"] = ISO8601DateFormatter().string(from: at) }
            if !item.repeatDays.isEmpty { out["repeatDays"] = item.repeatDays }
            return out
        }

        guard let data = try? JSONSerialization.data(withJSONObject: state,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        write(data, to: stateURL)
    }

    private func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // One line per failure, no per-write spam — same rule the stores follow.
            Self.log.error("agent file write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
