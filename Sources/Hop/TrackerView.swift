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
        case newRootTask            // a project-less root task
        case renameProject(UUID)
        case renameTask(UUID)
        case editToday(UUID)        // taskID
    }

    /// What a drag handle is currently moving.
    private enum DragRef: Hashable {
        case project(UUID)
        case task(UUID)
    }

    /// A measured row, keyed so its frame in the list coordinate space can be
    /// looked up when resolving a drop (mixed row heights make fixed shift math
    /// unreliable, so drops resolve against these frames — the 8.2 settings-table
    /// pattern).
    private enum RowRef: Hashable {
        case project(UUID)
        case task(UUID)
        case addTask(UUID)          // the "+ new task" row inside an expanded project
    }

    /// The resolved destination of an in-flight drag.
    private enum DropTarget: Equatable {
        case root(Int)                  // insert at this index in the mixed root list
        case intoProject(UUID, Int)     // insert into this project's task list at index
    }

    private struct RowFrameKey: PreferenceKey {
        static let defaultValue: [RowRef: CGRect] = [:]
        static func reduce(value: inout [RowRef: CGRect], nextValue: () -> [RowRef: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    private static let listSpace = "trackerList"

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

    // Drag-to-reorder: a handle at each row's left edge lifts a project or task;
    // the drop resolves against measured row frames (mixed heights). One engine
    // move commits per completed drag.
    @State private var dragRef: DragRef?
    @State private var dragTranslation: CGSize = .zero
    @State private var dropTarget: DropTarget?
    @State private var rowFrames: [RowRef: CGRect] = [:]

    private var draggingID: UUID? {
        switch dragRef {
        case .project(let id): return id
        case .task(let id): return id
        case nil: return nil
        }
    }

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
        let rootIDs = engine.data.rootOrder
        let projectByID = Dictionary(engine.data.projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rootTaskByID = Dictionary(engine.data.tasks.filter { $0.projectID == nil }.map { ($0.id, $0) },
                                      uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 6) {
            if rootIDs.isEmpty {
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
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            // The mixed root list: a project id renders its accordion block; a
            // project-less task id renders a task row at root indentation.
            ForEach(rootIDs, id: \.self) { id in
                if let project = projectByID[id] {
                    projectRow(project)
                    if project.isExpanded {
                        ForEach(tasks(of: project.id)) { task in
                            taskRow(task, nested: true)
                        }
                        addTaskRow(project.id)
                    }
                } else if let task = rootTaskByID[id] {
                    taskRow(task, nested: false)
                }
            }
            addRootTaskRow
            addProjectRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: Self.listSpace)
        .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
        .overlay(alignment: .topLeading) { dropIndicatorOverlay }
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
            resetDrag()
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
            } else if isEditing(.renameProject(project.id)) {
                nameField(.renameProject(project.id), placeholder: project.name)
            } else {
                HStack(spacing: 6) {
                    dragHandle(.project(project.id), id: project.id)
                    chevron(project)
                    Text(project.name)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2) { beginRenameProject(project) }
                    Spacer(minLength: 6)
                    // Summary times only while COLLAPSED — an expanded project
                    // already shows every task's own numbers, so repeating the
                    // rolled-up pair here was just four figures ticking as noise.
                    if !project.isExpanded {
                        Text("\(shortTime(engine.today(projectID: project.id))) — \(shortTime(engine.total(projectID: project.id)))")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                            .fixedSize()
                    }
                    HoverDeleteX(visible: hovered == project.id) { confirmingDeleteProject = project.id }
                }
                .contentShape(Rectangle())
                .onTapGesture { engine.setExpanded(projectID: project.id, !project.isExpanded) }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(rowFrameReader(.project(project.id)))
        .opacity(draggingID == project.id ? 0.4 : 1)
        .offset(draggingID == project.id ? dragTranslation : .zero)
        .zIndex(draggingID == project.id ? 2 : 0)
        .onHover { inside in
            if inside { hovered = project.id } else if hovered == project.id { hovered = nil }
        }
    }

    private func chevron(_ project: TrackerProject) -> some View {
        Button {
            engine.setExpanded(projectID: project.id, !project.isExpanded)
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .rotationEffect(.degrees(project.isExpanded ? 90 : 0))
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: project.isExpanded)
    }

    // MARK: - Task row

    @ViewBuilder private func taskRow(_ task: TrackerTask, nested: Bool) -> some View {
        let active = engine.activeTaskID == task.id
        Group {
            if confirmingDeleteTask == task.id {
                deleteConfirm(.trackerDeleteTask,
                              confirm: {
                                  engine.deleteTask(task.id)
                                  confirmingDeleteTask = nil
                              },
                              cancel: { confirmingDeleteTask = nil })
            } else if isEditing(.renameTask(task.id)) {
                nameField(.renameTask(task.id), placeholder: task.name)
            } else if isEditing(.editToday(task.id)) {
                // typing today's time: the field + its ✓/✕ own the row's tail,
                // so the total and delete step aside for a clean edit line.
                HStack(spacing: 6) {
                    dragHandle(.task(task.id), id: task.id)
                    playStop(task, active: active)
                    taskName(task)
                    Spacer(minLength: 6)
                    todayField(task)
                }
            } else {
                HStack(spacing: 6) {
                    dragHandle(.task(task.id), id: task.id)
                    playStop(task, active: active)
                    taskName(task)
                    Spacer(minLength: 6)
                    todayView(task, active: active)
                    // total prefixed with Σ so the pair reads as two different
                    // things at a glance: today's time, then the running sum.
                    Text("Σ \(shortTime(engine.total(taskID: task.id)))")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .fixedSize()
                    HoverDeleteX(visible: hovered == task.id) { confirmingDeleteTask = task.id }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, nested ? 16 : 2)   // nested tasks indent under the project; root tasks align with it
        .padding(.trailing, 2)
        .background(rowFrameReader(.task(task.id)))
        .opacity(draggingID == task.id ? 0.4 : 1)
        .offset(draggingID == task.id ? dragTranslation : .zero)
        .zIndex(draggingID == task.id ? 2 : 0)
        .onHover { inside in
            if inside { hovered = task.id } else if hovered == task.id { hovered = nil }
        }
    }

    private func playStop(_ task: TrackerTask, active: Bool) -> some View {
        Button {
            // the engine stops the previously active task itself (single-active)
            active ? engine.stopActive() : engine.start(taskID: task.id)
        } label: {
            // same play/pause family as the main timer button: filled circle
            // offers "start" (play), bordered circle offers "pause". Scaled to
            // the task row.
            TransportCircle(systemName: active ? "pause.fill" : "play.fill",
                            filled: !active, diameter: 22, iconSize: 9)
        }
        .buttonStyle(.plain)
        .hoverDim()
    }

    // Rename is a row-level branch (see taskRow), so the name here is display-only.
    private func taskName(_ task: TrackerTask) -> some View {
        Text(task.name)
            .font(Theme.mono(12))
            .foregroundStyle(Theme.listText)
            .lineLimit(1)
            .truncationMode(.tail)
            .onTapGesture(count: 2) { beginRenameTask(task) }
    }

    // MARK: - Today value (emphasis while active; scrub/type while idle)

    // The editing branch lives in `taskRow` (it reshapes the whole row); this is
    // only the read/scrub/tap-to-edit label.
    @ViewBuilder private func todayView(_ task: TrackerTask, active: Bool) -> some View {
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

    private func todayField(_ task: TrackerTask) -> some View {
        HStack(spacing: 4) {
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
            FieldCommitButtons(onCommit: { commitToday(task.id) }, onCancel: { endEdit() })
        }
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

    // MARK: - Drag to reorder

    /// A burger handle at the row's left edge. Kept in the layout as a fixed
    /// gutter (opacity, not conditional removal) so an in-flight drag's gesture
    /// view survives the pointer leaving the row; only interactive when shown.
    private func dragHandle(_ ref: DragRef, id: UUID) -> some View {
        let shown = hovered == id || draggingID == id
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .frame(width: 14, height: 18)
            .contentShape(Rectangle())
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .gesture(dragGesture(ref))
    }

    private func dragGesture(_ ref: DragRef) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if dragRef == nil {
                    dragRef = ref
                    // a drag must not fight an open field or a pending confirm
                    endEdit()
                    clearConfirms()
                }
                dragTranslation = value.translation
                dropTarget = resolveDrop(ref, at: value.location.y)
            }
            .onEnded { value in
                commitDrop(ref, resolveDrop(ref, at: value.location.y))
                resetDrag()
            }
    }

    /// Resolves a pointer y (in list space) to a drop target. A task can land in
    /// the mixed root list, between an expanded project's tasks, or onto a
    /// collapsed project (append); a project only ever lands among root items.
    private func resolveDrop(_ ref: DragRef, at y: CGFloat) -> DropTarget? {
        if case .task(let tid) = ref {
            // onto a collapsed project row = append into that project
            for project in engine.data.projects where !project.isExpanded {
                if let f = rowFrames[.project(project.id)], y >= f.minY, y <= f.maxY {
                    let count = engine.data.tasks.filter { $0.projectID == project.id && $0.id != tid }.count
                    return .intoProject(project.id, count)
                }
            }
            // inside an expanded project (header bottom .. add-task row bottom)
            for project in engine.data.projects where project.isExpanded {
                guard let header = rowFrames[.project(project.id)] else { continue }
                let bottom = interiorBottom(of: project.id) ?? header.maxY
                if y > header.maxY, y <= bottom {
                    let siblings = tasks(of: project.id).filter { $0.id != tid }
                    let idx = siblings.filter { (rowFrames[.task($0.id)]?.midY ?? .greatestFiniteMagnitude) < y }.count
                    return .intoProject(project.id, idx)
                }
            }
        }
        // a position in the mixed root list: count the OTHER root blocks above y
        let others = engine.data.rootOrder.filter { $0 != draggingID }
        let idx = others.filter { blockMidY(of: $0) < y }.count
        return .root(idx)
    }

    private func commitDrop(_ ref: DragRef, _ target: DropTarget?) {
        guard let target else { return }
        switch (ref, target) {
        case (.task(let tid), .root(let idx)):
            engine.move(taskID: tid, toRootAt: idx)
        case (.task(let tid), .intoProject(let pid, let idx)):
            engine.move(taskID: tid, toProjectID: pid, at: idx)
        case (.project(let pid), .root(let idx)):
            if let from = engine.data.rootOrder.firstIndex(of: pid) {
                engine.moveRootItem(from: from, to: idx)
            }
        case (.project, .intoProject):
            break   // projects never nest
        }
    }

    private func resetDrag() {
        dragRef = nil
        dragTranslation = .zero
        dropTarget = nil
    }

    // Geometry helpers over the measured row frames.

    /// The bottom edge of an expanded project's interior: its add-task row, or
    /// the last task, or nil when nothing is measured yet.
    private func interiorBottom(of projectID: UUID) -> CGFloat? {
        rowFrames[.addTask(projectID)]?.maxY
            ?? tasks(of: projectID).compactMap { rowFrames[.task($0.id)]?.maxY }.max()
    }

    /// The vertical middle of a root item's whole block (an expanded project
    /// spans header..interior; a collapsed project or a task is just its row).
    private func blockMidY(of id: UUID) -> CGFloat {
        if let project = engine.data.projects.first(where: { $0.id == id }) {
            guard let header = rowFrames[.project(id)] else { return .greatestFiniteMagnitude }
            if project.isExpanded, let bottom = interiorBottom(of: id) {
                return (header.minY + bottom) / 2
            }
            return header.midY
        }
        return rowFrames[.task(id)]?.midY ?? .greatestFiniteMagnitude
    }

    private func blockTop(of id: UUID?) -> CGFloat? {
        guard let id else { return nil }
        if engine.data.projects.contains(where: { $0.id == id }) { return rowFrames[.project(id)]?.minY }
        return rowFrames[.task(id)]?.minY
    }

    private func blockBottom(of id: UUID?) -> CGFloat? {
        guard let id else { return nil }
        if let project = engine.data.projects.first(where: { $0.id == id }) {
            if project.isExpanded { return interiorBottom(of: id) ?? rowFrames[.project(id)]?.maxY }
            return rowFrames[.project(id)]?.maxY
        }
        return rowFrames[.task(id)]?.maxY
    }

    /// The y at which to draw the drop indicator line for the resolved target.
    private func indicatorY(for target: DropTarget) -> CGFloat? {
        switch target {
        case .root(let idx):
            let ids = engine.data.rootOrder.filter { $0 != draggingID }
            if ids.isEmpty { return nil }
            if idx <= 0 { return blockTop(of: ids.first) }
            if idx >= ids.count { return blockBottom(of: ids.last) }
            if let a = blockBottom(of: ids[idx - 1]), let b = blockTop(of: ids[idx]) { return (a + b) / 2 }
            return blockBottom(of: ids[idx - 1]) ?? blockTop(of: ids[idx])
        case .intoProject(let pid, let idx):
            let sib = tasks(of: pid).filter { $0.id != draggingID }
            if sib.isEmpty { return rowFrames[.addTask(pid)]?.minY ?? rowFrames[.project(pid)]?.maxY }
            if idx <= 0 { return rowFrames[.task(sib.first!.id)]?.minY }
            if idx >= sib.count { return rowFrames[.addTask(pid)]?.minY ?? rowFrames[.task(sib.last!.id)]?.maxY }
            if let a = rowFrames[.task(sib[idx - 1].id)]?.maxY, let b = rowFrames[.task(sib[idx].id)]?.minY {
                return (a + b) / 2
            }
            return rowFrames[.task(sib[idx].id)]?.minY
        }
    }

    @ViewBuilder private var dropIndicatorOverlay: some View {
        if let target = dropTarget, let y = indicatorY(for: target) {
            let intoProject: Bool = { if case .intoProject = target { return true } else { return false } }()
            Rectangle()
                .fill(Theme.editing)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .padding(.leading, intoProject ? 16 : 0)
                .offset(y: y - 1)
                .allowsHitTesting(false)
        }
    }

    private func rowFrameReader(_ ref: RowRef) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: RowFrameKey.self,
                                   value: [ref: geo.frame(in: .named(Self.listSpace))])
        }
    }

    // MARK: - Add affordances

    @ViewBuilder private var addProjectRow: some View {
        if isEditing(.newProject) {
            nameField(.newProject, placeholder: t(.trackerNewProject))
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
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
                    .padding(.vertical, 4)
            } else {
                Button { beginNewTask(projectID) } label: {
                    addRowLabel(t(.trackerNewTask), iconSize: 9)
                }
                .buttonStyle(.plain)
                .hoverHighlight(6)
            }
        }
        .padding(.leading, 16)
        // measured so an expanded project's interior (drop zone) is bounded at
        // the bottom even when it has no task rows.
        .background(rowFrameReader(.addTask(projectID)))
    }

    /// A project-less "+ new task" at the root, beside "+ new project".
    @ViewBuilder private var addRootTaskRow: some View {
        if isEditing(.newRootTask) {
            nameField(.newRootTask, placeholder: t(.trackerNewTask))
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
        } else {
            Button { beginNewRootTask() } label: {
                addRowLabel(t(.trackerNewTask), iconSize: 10)
            }
            .buttonStyle(.plain)
            .hoverHighlight(6)
        }
    }

    private func addRowLabel(_ text: String, iconSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: iconSize, weight: .semibold))
            Text(text).font(Theme.mono(11))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 2)
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

    private func nameField(_ field: Field, placeholder: String) -> some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $nameDraft)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
                .focused($focused, equals: field)
                .onAppear { focused = field }
                .onSubmit { commitName() }
                .onExitCommand { endEdit() }
            FieldCommitButtons(onCommit: { commitName() }, onCancel: { endEdit() })
        }
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

    private func beginNewRootTask() {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = ""
        activeField = .newRootTask
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
        case .newRootTask: engine.addTask(projectID: nil, name: name)
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
