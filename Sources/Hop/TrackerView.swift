import SwiftUI
import HopCore

/// Time-tracker module: projects as accordions, tasks with play/stop, a
/// "today — total" glance per row, and inline editing of names and today's
/// time (scrub or type). All state lives in the engine (single-active
/// invariant, aggregates, corrections); this view is glue. Visual language
/// follows TorrentView's rows and ClipboardView's list — Theme tokens only,
/// no infinite animations. Labels tick off `tracker.heartbeat` while running.
struct TrackerView: View {
    @ObservedObject var tracker: TrackerController
    let lang: AppLanguage
    /// Fired whenever an inline field opens (true) or closes (false), so the
    /// panel can hold the keyboard while typing a name — otherwise Return in a
    /// project field reaches the panel's global key handler and starts the timer.
    var onEditingChanged: ((Bool) -> Void)? = nil

    /// The single field currently accepting text: a new-name entry, a rename,
    /// or a today-time edit. Only one is ever open, so one draft per kind
    /// suffices. Gated off `Snapshot.active` so demo renders never show a field.
    private enum Field: Hashable {
        case newProject
        case newTask(UUID)          // projectID
        case renameProject(UUID)
        case renameTask(UUID)
        case editToday(UUID)        // taskID
    }

    @State private var activeField: Field?
    @State private var nameDraft = ""
    @State private var todayDraft = ""
    @FocusState private var focused: Field?

    @State private var confirmingDeleteProject: UUID?
    @State private var confirmingDeleteTask: UUID?
    // Which row's trailing xmark is revealed; ids are unique across projects
    // and tasks, so one slot covers both.
    @State private var hovered: UUID?

    // Scrub-to-edit-today: preview a pending value locally and commit ONE
    // correction on gesture end (the engine appends corrections, so a
    // per-step commit would write one per tick).
    @State private var scrubbingTask: UUID?
    @State private var scrubBase: TimeInterval?
    @State private var scrubPending: TimeInterval?
    @State private var scrubSteps = 0

    private var engine: TrackerEngine { tracker.engine }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private func shortTime(_ v: TimeInterval) -> String { TimeFormatting.short(v) }
    private func tasks(of projectID: UUID) -> [TrackerTask] {
        engine.data.tasks.filter { $0.projectID == projectID }
    }
    /// A field is only "editing" outside snapshots — keeps yellow TextField
    /// artifacts out of `--snapshot` renders.
    private func isEditing(_ field: Field) -> Bool {
        !Snapshot.active && activeField == field
    }

    var body: some View {
        // read the heartbeat so every label recomputes while a task is tracking
        let _ = tracker.heartbeat
        let projects = engine.data.projects
        return VStack(alignment: .leading, spacing: 6) {
            if projects.isEmpty {
                // Name the feature above the hint: this space is otherwise a
                // bare "no projects yet" with nothing saying what it is.
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(.trackerLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Text(t(.trackerEmpty))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            ForEach(projects) { project in
                projectRow(project)
                if project.isExpanded {
                    ForEach(tasks(of: project.id)) { task in
                        taskRow(task)
                    }
                    addTaskRow(project.id)
                }
            }
            addProjectRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // `activeField` is the single source of truth for "a field is open"
        // (begin* sets it, endEdit clears it, including via commit/Escape and
        // onDisappear below) — so one place reports editing to the panel.
        .onChange(of: activeField) { _, field in
            onEditingChanged?(field != nil && !Snapshot.active)
        }
        .onDisappear {
            // @State survives the popover hide/show, so a left-open field or
            // confirm row would reappear (unfocused) on the next open — clear
            // it here, the same way PanelView drops its inline icon picker.
            endEdit()
            clearConfirms()
            resetScrub()
        }
    }

    // MARK: - Project row

    @ViewBuilder private func projectRow(_ project: TrackerProject) -> some View {
        Group {
            if confirmingDeleteProject == project.id {
                deleteConfirm(.trackerDeleteProject,
                              confirm: {
                                  engine.deleteProject(project.id)
                                  confirmingDeleteProject = nil
                              },
                              cancel: { confirmingDeleteProject = nil })
            } else {
                HStack(spacing: 6) {
                    chevron(project)
                    projectName(project)
                    Spacer(minLength: 6)
                    Text("\(shortTime(engine.today(projectID: project.id))) — \(shortTime(engine.total(projectID: project.id)))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .fixedSize()
                    deleteX(project.id) { confirmingDeleteProject = project.id }
                }
                .contentShape(Rectangle())
                .onTapGesture { engine.setExpanded(projectID: project.id, !project.isExpanded) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 20)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .onHover { inside in
            if inside { hovered = project.id } else if hovered == project.id { hovered = nil }
        }
    }

    private func chevron(_ project: TrackerProject) -> some View {
        Button {
            engine.setExpanded(projectID: project.id, !project.isExpanded)
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .rotationEffect(.degrees(project.isExpanded ? 90 : 0))
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: project.isExpanded)
    }

    @ViewBuilder private func projectName(_ project: TrackerProject) -> some View {
        if isEditing(.renameProject(project.id)) {
            nameField(.renameProject(project.id), placeholder: project.name)
        } else {
            Text(project.name)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { beginRenameProject(project) }
        }
    }

    // MARK: - Task row

    @ViewBuilder private func taskRow(_ task: TrackerTask) -> some View {
        let active = engine.activeTaskID == task.id
        Group {
            if confirmingDeleteTask == task.id {
                deleteConfirm(.trackerDeleteTask,
                              confirm: {
                                  engine.deleteTask(task.id)
                                  confirmingDeleteTask = nil
                              },
                              cancel: { confirmingDeleteTask = nil })
            } else {
                HStack(spacing: 6) {
                    playStop(task, active: active)
                    taskName(task)
                    Spacer(minLength: 6)
                    todayView(task, active: active)
                    Text(shortTime(engine.total(taskID: task.id)))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .fixedSize()
                    deleteX(task.id) { confirmingDeleteTask = task.id }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 14)   // nest under the expanded project
        .onHover { inside in
            if inside { hovered = task.id } else if hovered == task.id { hovered = nil }
        }
    }

    private func playStop(_ task: TrackerTask, active: Bool) -> some View {
        Button {
            // the engine stops the previously active task itself (single-active)
            active ? engine.stopActive() : engine.start(taskID: task.id)
        } label: {
            Image(systemName: active ? "stop.fill" : "play.fill")
                .font(.system(size: 11))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    @ViewBuilder private func taskName(_ task: TrackerTask) -> some View {
        if isEditing(.renameTask(task.id)) {
            nameField(.renameTask(task.id), placeholder: task.name)
        } else {
            Text(task.name)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.listText)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { beginRenameTask(task) }
        }
    }

    // MARK: - Today value (emphasis while active; scrub/type while idle)

    @ViewBuilder private func todayView(_ task: TrackerTask, active: Bool) -> some View {
        if isEditing(.editToday(task.id)) {
            todayField(task)
        } else {
            let value = (scrubbingTask == task.id ? (scrubPending ?? engine.today(taskID: task.id))
                                                  : engine.today(taskID: task.id))
            let label = Text(shortTime(value))
                .font(Theme.mono(11))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                .monospacedDigit()
                .fixedSize()
            if active {
                // active task: the engine refuses edits, so no affordance is offered
                label
            } else {
                label
                    .contentShape(Rectangle())
                    .help(t(.trackerEditHint))
                    .simultaneousGesture(TapGesture().onEnded { beginEditToday(task) })
                    .simultaneousGesture(todayScrub(task.id))
            }
        }
    }

    private func todayField(_ task: TrackerTask) -> some View {
        TextField("", text: $todayDraft)
            .textFieldStyle(.plain)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(width: 54)
            .focused($focused, equals: .editToday(task.id))
            .onAppear { focused = .editToday(task.id) }
            .onSubmit { commitToday(task.id) }
            .onExitCommand { endEdit() }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 4))
    }

    /// Each 8pt of horizontal travel = ±1 minute, a tick per step; the running
    /// preview lives in `scrubPending` and commits as ONE correction on end.
    private func todayScrub(_ taskID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard engine.activeTaskID != taskID else { return }
                if scrubbingTask != taskID {
                    scrubbingTask = taskID
                    scrubBase = engine.today(taskID: taskID)
                    scrubSteps = 0
                }
                let steps = Int((value.translation.width / 8).rounded())
                if steps != scrubSteps {
                    scrubSteps = steps
                    Sounds.scrubTick()
                }
                scrubPending = max(0, (scrubBase ?? 0) + Double(steps) * 60)
            }
            .onEnded { _ in
                // a drag that returns to origin (steps == 0) is a no-op — don't
                // append a 0-second correction to tracker.json for nothing.
                if let taskID = scrubbingTask, let pending = scrubPending, scrubSteps != 0 {
                    engine.setToday(taskID: taskID, to: pending)
                }
                resetScrub()
            }
    }

    private func resetScrub() {
        scrubbingTask = nil
        scrubBase = nil
        scrubPending = nil
        scrubSteps = 0
    }

    // MARK: - Add affordances

    @ViewBuilder private var addProjectRow: some View {
        if isEditing(.newProject) {
            nameField(.newProject, placeholder: t(.trackerNewProject))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        } else {
            Button { beginNewProject() } label: {
                addRowLabel(t(.trackerNewProject), iconSize: 10)
            }
            .buttonStyle(.plain)
            .hoverHighlight(6)
        }
    }

    @ViewBuilder private func addTaskRow(_ projectID: UUID) -> some View {
        Group {
            if isEditing(.newTask(projectID)) {
                nameField(.newTask(projectID), placeholder: t(.trackerNewTask))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            } else {
                Button { beginNewTask(projectID) } label: {
                    addRowLabel(t(.trackerNewTask), iconSize: 9)
                }
                .buttonStyle(.plain)
                .hoverHighlight(6)
            }
        }
        .padding(.leading, 14)
    }

    private func addRowLabel(_ text: String, iconSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: iconSize, weight: .semibold))
            Text(text).font(Theme.mono(11))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    // MARK: - Shared pieces

    private func deleteConfirm(_ question: L10nKey,
                               confirm: @escaping () -> Void,
                               cancel: @escaping () -> Void) -> some View {
        // question on the left; "cancel" sits rightmost, away from "delete",
        // so a reflexive tap doesn't land on the destructive option.
        HStack(spacing: 12) {
            Text(t(question))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            Button(action: confirm) {
                HoverLabel(text: t(.trackerDelete), size: 10, color: Theme.accentRed)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: cancel) {
                HoverLabel(text: t(.quitCancel), size: 10, color: Theme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Trailing delete affordance, revealed on row hover. Kept out of hit-testing
    /// while hidden so the invisible glyph can't be clicked.
    private func deleteX(_ id: UUID, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
        .opacity(hovered == id ? 1 : 0)
        .allowsHitTesting(hovered == id)
    }

    private func nameField(_ field: Field, placeholder: String) -> some View {
        TextField(placeholder, text: $nameDraft)
            .textFieldStyle(.plain)
            .font(Theme.mono(12))
            .foregroundStyle(Theme.textPrimary)
            .focused($focused, equals: field)
            .onAppear { focused = field }
            .onSubmit { commitName() }
            .onExitCommand { endEdit() }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Edit lifecycle

    private func beginNewProject() {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = ""
        activeField = .newProject
    }

    private func beginNewTask(_ projectID: UUID) {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = ""
        activeField = .newTask(projectID)
    }

    private func beginRenameProject(_ project: TrackerProject) {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = project.name
        activeField = .renameProject(project.id)
    }

    private func beginRenameTask(_ task: TrackerTask) {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = task.name
        activeField = .renameTask(task.id)
    }

    private func beginEditToday(_ task: TrackerTask) {
        guard !Snapshot.active, engine.activeTaskID != task.id else { return }
        clearConfirms()
        let total = Int(engine.today(taskID: task.id))
        let h = total / 3600
        let m = (total % 3600) / 60
        // prefill in the same lenient shape the parser reads back
        todayDraft = h > 0 ? "\(h):\(String(format: "%02d", m))" : "\(m)"
        activeField = .editToday(task.id)
    }

    private func commitName() {
        defer { endEdit() }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }   // empty input = cancel
        switch activeField {
        case .newProject: engine.addProject(name: name)
        case .newTask(let projectID): engine.addTask(projectID: projectID, name: name)
        case .renameProject(let id): engine.renameProject(id, to: name)
        case .renameTask(let id): engine.renameTask(id, to: name)
        default: break
        }
    }

    private func commitToday(_ taskID: UUID) {
        defer { endEdit() }
        guard let seconds = parseToday(todayDraft) else { return }
        engine.setToday(taskID: taskID, to: seconds)
    }

    private func endEdit() {
        activeField = nil
        focused = nil
        nameDraft = ""
        todayDraft = ""
    }

    private func clearConfirms() {
        confirmingDeleteProject = nil
        confirmingDeleteTask = nil
    }

    /// "90" → 90 minutes; "1:30" → 1h30m. Both resolve to the same seconds.
    /// Returns nil for empty or unparseable input (treated as cancel).
    private func parseToday(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let h = Int(parts[0]) else { return nil }
            let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            return TimeInterval(h * 3600 + m * 60)
        }
        guard let minutes = Int(trimmed) else { return nil }
        return TimeInterval(minutes * 60)
    }
}
