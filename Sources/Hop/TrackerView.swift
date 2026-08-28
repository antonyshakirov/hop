import SwiftUI
import HopCore

/// Time-tracker module: tasks with play/stop and a figure per row (ticking
/// while active) for whichever period the header selects, optionally grouped
/// into projects that carry their own sum; inline rename and figure-editing
/// (scrub or type), whole-row drag to reorder and to move a task in or out of a
/// project, and an 8-hour "still tracking" warning under a long-running task.
/// All state lives in the engine (single-active invariant, aggregates,
/// corrections) and the drop maths in `TrackerDrop`; this view is glue. Visual
/// follows TorrentView's rows — Theme tokens only, no infinite animations.
/// Row rhythm matches the to-dos list exactly (VStack spacing 3,
/// `.padding(.vertical, 2)`), so the near-twin modules read identically when
/// stacked on one space. Labels tick off `tracker.heartbeat` while running.
struct TrackerView: View {
    @ObservedObject var tracker: TrackerController
    let lang: AppLanguage
    /// Fired whenever an inline field opens (true) or closes (false), so the
    /// panel can hold the keyboard while typing — otherwise Return in a task
    /// field reaches the panel's global key handler and starts the timer.
    var onEditingChanged: ((Bool) -> Void)? = nil

    /// The single field currently accepting text: a new-task entry, a rename,
    /// or a total-time edit. Only one is ever open, so one draft per kind
    /// suffices. Gated off `Snapshot.active` so demo renders never show a field.
    private enum Field: Hashable {
        case newTask
        case newTaskIn(UUID)        // projectID — the add row inside a project
        case newProject
        case renameProject(UUID)    // projects have no card, so renaming is inline
        case editTotal(UUID)        // taskID
        case editEntry(UUID)        // one line of a task's history
        case newEntry(UUID)         // taskID — a session being added by hand
    }

    private struct RowFrameKey: PreferenceKey {
        static let defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    private static let listSpace = "trackerList"

    @State private var activeField: Field?
    @State private var nameDraft = ""
    @State private var totalDraft = ""
    @FocusState private var focused: Field?

    @State private var confirmingDeleteTask: UUID?
    @State private var confirmingDeleteProject: UUID?
    // Which task is expanded into its card, and the draft it is editing. One card
    // at a time, exactly like the to-do list.
    @State private var expandedTask: UUID?
    @State private var card: TaskCardDraft?
    // Which row's trailing xmark is revealed (hover-only).
    @State private var hovered: UUID?

    // Scrub-to-edit-total: preview a pending value locally and commit ONE
    // correction on gesture end (the engine appends corrections, so a
    // per-step commit would write one per tick).
    @State private var scrubbingTask: UUID?
    @State private var scrubBase: TimeInterval?
    @State private var scrubPending: TimeInterval?
    @State private var scrubSteps = 0
    // Latched when a total-scrub drag turns out to be vertical-dominant — that's
    // a row reorder, so the scrub stands down for the rest of the gesture.
    @State private var scrubRejected = false

    // Drag-to-reorder: a vertical drag anywhere on a row lifts it; the drop
    // resolves against measured row frames. One engine move per completed drag.
    // A horizontal-dominant drag is left to the total label's scrub (axis gate).
    // A project travels with its own tasks — the drop maths is told which kind
    // is moving, and excludes them.
    @State private var dragTask: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dropTarget: TrackerDrop.Target?
    @State private var rowFrames: [UUID: CGRect] = [:]
    // Latched when a reorder drag's first move is horizontal-dominant — that's a
    // total scrub, so this row-reorder gesture stands down for the rest of it.
    @State private var dragRejected = false

    /// "visible rows" cap: 0 = all (default), 3…15 caps the task list to a fixed
    /// height with inner scroll (the 8h warning is pinned outside the scroll).
    @AppStorage(TrackerController.visibleRowsKey) private var visibleRows = TrackerController.defaultVisibleRows
    /// Float important tasks to the top. OFF by default — the mark alone moves
    /// nothing, which keeps the hand-built order the user's own.
    @AppStorage(SettingsKey.trackerImportantOnTop) private var importantOnTop = false
    /// Which period every figure in the module covers.
    @AppStorage(TrackerController.periodKey) private var periodRaw = TrackerPeriod.total.rawValue
    /// The week's first day: read only so a change recuts the week figures.
    @AppStorage(SettingsKey.firstWeekday) private var firstWeekday = FirstWeekday.auto

    private var engine: TrackerEngine { tracker.engine }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private func shortTime(_ v: TimeInterval) -> String { TimeFormatting.short(v) }

    private var period: TrackerPeriod { TrackerPeriod(rawValue: periodRaw) ?? .total }

    /// One visible line of the list. A project's tasks are only here while it
    /// is unfolded, which is what makes this the truth the drop maths measures.
    private struct DisplayRow: Identifiable {
        let id: UUID
        let project: TrackerProject?
        let task: TrackerTask?
        /// The project a task sits in, nil at the top level.
        let parent: UUID?
    }

    private var displayRows: [DisplayRow] {
        let floating = importantOnTop && !Snapshot.active
        var rows: [DisplayRow] = []
        for item in TrackerDisplay.order(topLevel: engine.topLevel, importantFirst: floating) {
            switch item {
            case .task(let task):
                rows.append(DisplayRow(id: task.id, project: nil, task: task, parent: nil))
            case .project(let project):
                rows.append(DisplayRow(id: project.id, project: project, task: nil, parent: nil))
                guard project.isExpanded else { continue }
                let tasks = TrackerDisplay.order(engine.tasks(in: project.id), importantFirst: floating)
                rows.append(contentsOf: tasks.map {
                    DisplayRow(id: $0.id, project: nil, task: $0, parent: project.id)
                })
            }
        }
        return rows
    }

    /// A field is only "editing" outside snapshots — keeps yellow TextField
    /// artifacts out of `--snapshot` renders.
    private func isEditing(_ field: Field) -> Bool {
        !Snapshot.active && activeField == field
    }

    /// True when the task list overflows an active cap and therefore scrolls.
    /// While it scrolls the whole-row reorder drag stands down (the pan scrolls
    /// instead) — reorder is for the short, fully-visible list; the total-scrub
    /// (horizontal) and play/stop taps keep working.
    private var trackerCapped: Bool {
        !Snapshot.active && RowCap.scrolls(stored: visibleRows, count: displayRows.count)
    }

    var body: some View {
        // read the heartbeat so every label (and the 8h warning) recomputes
        // while a task is tracking
        let _ = tracker.heartbeat
        let rows = displayRows
        let capped = trackerCapped
        let taskRows = VStack(alignment: .leading, spacing: 3) {
            ForEach(rows) { row in
                if let project = row.project {
                    projectRow(project)
                    // a project's own add row, only while it is unfolded and
                    // the field is open on it
                    if project.isExpanded, isEditing(.newTaskIn(project.id)) {
                        nameField(.newTaskIn(project.id), placeholder: t(.trackerNewTask))
                            .padding(.leading, Self.projectIndent)
                    }
                } else if let task = row.task {
                    taskRow(task, indented: row.parent != nil)
                    // inline warning only when NOT capped; when the list scrolls
                    // it is pinned below (see the branch) so it never scrolls away
                    if !capped, isLongRun(task.id) { longRunRow(task.id) }
                }
            }
        }
        return VStack(alignment: .leading, spacing: 3) {
            // An empty list shows only the subheader and the add row — the
            // subheader already names the module, so no placeholder line.
            // The subheader, the pinned 8h warning and the add row stay OUTSIDE
            // the scroll; only the task list scrolls, at exactly cap rows plus
            // their gaps — 29·cap − 3.
            subheader
            if capped, let height = RowCap.listHeight(stored: visibleRows, count: rows.count) {
                ScrollView(showsIndicators: false) { taskRows }
                    .frame(height: height)
                // the single active task's 8h "still tracking?" warning stays
                // visible, pinned directly under the scrolling list
                if let longID = rows.first(where: { isLongRun($0.id) })?.id { longRunRow(longID) }
            } else {
                taskRows
            }
            addRows
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: Self.listSpace)
        .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
        .overlay(alignment: .topLeading) { dropIndicatorOverlay }
        // the week is cut by the user's own first weekday, which can change
        // while the panel is open
        .onAppear { tracker.refreshWeekStart() }
        .onChange(of: firstWeekday) { _, _ in tracker.refreshWeekStart() }
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
            collapseCard()
            resetScrub()
            resetDrag()
        }
    }

    // MARK: - Module subheader

    /// The indent a project's contents sit at — enough to read as "inside"
    /// without pushing the names off a narrow panel.
    private static let projectIndent: CGFloat = 16

    /// A compact module sublabel above the list — same treatment as the settings
    /// section headers (mono 10 semibold, tertiary, lowercase), so the tracker
    /// and to-do lists are distinguishable at a glance when stacked on one space.
    /// The period switch shares the line: it belongs to every figure below it,
    /// and a row of its own would cost 26pt of a panel that has none to spare.
    private var subheader: some View {
        HStack(spacing: 6) {
            Text(t(.trackerLabel))
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 6)
            ForEach(TrackerPeriod.allCases, id: \.self) { option in
                Button { periodRaw = option.rawValue } label: {
                    Text(t(periodLabel(option)))
                        .font(Theme.mono(10, weight: period == option ? .semibold : .regular))
                        .foregroundStyle(period == option ? Theme.textPrimary : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .hoverDim()
            }
        }
    }

    private func periodLabel(_ period: TrackerPeriod) -> L10nKey {
        switch period {
        case .today: return .trackerPeriodToday
        case .week: return .trackerPeriodWeek
        case .total: return .trackerPeriodTotal
        }
    }

    // MARK: - Project row

    @ViewBuilder private func projectRow(_ project: TrackerProject) -> some View {
        if isEditing(.renameProject(project.id)) {
            nameField(.renameProject(project.id), placeholder: t(.trackerNewProject))
                .padding(.vertical, 2)
                .background(rowFrameReader(project.id))
        } else {
            let confirming = confirmingDeleteProject == project.id
            HStack(spacing: 6) {
                // A disclosure triangle, pointing the way the list will go —
                // the shape macOS uses for exactly this, so nobody has to learn
                // it (Anton, 2026-08-28).
                Button { engine.setProjectExpanded(project.id, !project.isExpanded) } label: {
                    // The SAME triangle the play buttons carry, minus the
                    // circle, on the SAME axis: centred in the circle's own
                    // 18pt box inside the 22pt gutter, so every arrow in the
                    // list sits on one vertical line (Anton, 2026-08-28).
                    PlayGlyph(color: Theme.glyphInk, box: RowCircle.diameter * 0.315)
                        // one layer, then the transparency: the glyph is a fill
                        // under a stroke, and a translucent colour would show
                        // their overlap as an outline
                        .compositingGroup()
                        .opacity(Theme.glyphInkSecondary)
                        .rotationEffect(.degrees(project.isExpanded ? 90 : 0))
                        .frame(width: RowCircle.diameter, height: RowCircle.gutter)
                        .frame(width: RowCircle.gutter, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                // Renaming lives on the NAME, not on the row: with the whole row
                // taking the tap, the triangle's own click was being swallowed
                // and folding a project started a rename instead (Anton,
                // 2026-08-28).
                Text(project.name)
                    .font(Theme.mono(12, weight: .semibold))
                    .foregroundStyle(Theme.listText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture { beginRenameProject(project) }
                // a folded project still has to show that something under it runs
                if !project.isExpanded, engine.isTracking(projectID: project.id) {
                    Circle()
                        .fill(Theme.accentGreen)
                        .frame(width: 5, height: 5)
                }
                Spacer(minLength: 6)
                if confirming {
                    // what is about to go, in glyphs rather than a sentence: a
                    // count of tasks needs a plural form in 22 languages, and
                    // the icons say it in none of them
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet").font(.system(size: 9))
                        Text("\(engine.tasks(in: project.id).count)")
                            .font(Theme.mono(10)).monospacedDigit()
                    }
                    .foregroundStyle(Theme.textTertiary)
                    RowDeleteConfirm(lang: lang,
                                     onDelete: {
                                         engine.deleteProject(project.id)
                                         confirmingDeleteProject = nil
                                     },
                                     onCancel: { confirmingDeleteProject = nil })
                } else if hovered == project.id {
                    // add a task straight into this project — the only route
                    // that does not involve dragging one in
                    Button {
                        engine.setProjectExpanded(project.id, true)
                        beginNewTaskIn(project.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverDim()
                    HoverDeleteX { confirmingDeleteProject = project.id }
                }
                Text(shortTime(engine.amount(projectID: project.id, period: period)))
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .fixedSize()
            }
            .padding(.vertical, 2)
            .background(rowFrameReader(project.id))
            .contentShape(Rectangle())
            .gesture(dragGesture(project.id, isProject: true),
                     including: trackerCapped ? .subviews : .all)
            .opacity(dragTask == project.id ? 0.4 : 1)
            .offset(dragTask == project.id ? dragTranslation : .zero)
            .zIndex(dragTask == project.id ? 2 : 0)
            .onHover { inside in
                if inside { hovered = project.id } else if hovered == project.id { hovered = nil }
            }
        }
    }

    // MARK: - Task row

    @ViewBuilder private func taskRow(_ task: TrackerTask, indented: Bool) -> some View {
        Group {
            if expandedTask == task.id, card != nil, !Snapshot.active {
                VStack(alignment: .leading, spacing: 6) {
                    TaskCardView(draft: Binding(get: { card ?? TaskCardDraft(text: task.name,
                                                                            note: task.note,
                                                                            important: task.important) },
                                                set: { card = $0 }),
                                 lang: lang,
                                 onCommit: { commitCard(task) },
                                 onCancel: { collapseCard() })
                    history(task)
                }
                    .background(rowFrameReader(task.id))
            } else {
                collapsedTaskRow(task)
            }
        }
        .padding(.leading, indented ? Self.projectIndent : 0)
    }

    @ViewBuilder private func collapsedTaskRow(_ task: TrackerTask) -> some View {
        let active = engine.activeTaskID == task.id
        // The hover xmark shows only in the normal display state — not while a
        // confirm or an inline field owns the row's tail.
        let showsHoverX = confirmingDeleteTask != task.id
            && !isEditing(.editTotal(task.id))
        Group {
            if confirmingDeleteTask == task.id {
                // Confirm keeps the row's silhouette AND the trailing time: the
                // play/stop circle, the name and the far-right time all stay put;
                // only the hover ✕ gives way to delete/cancel, rendered just left
                // of the (now inert) time. cancel takes the ✕'s EXACT slot (6pt
                // left of the time — the HStack's own spacing, same gap the ✕
                // had), delete sits 12pt further left — so a reflexive repeat
                // click at the ✕ point lands on cancel, never delete.
                HStack(spacing: 6) {
                    playStop(task, active: active)
                    taskName(task)
                    Spacer(minLength: 6)
                    RowDeleteConfirm(lang: lang,
                                     onDelete: {
                                         engine.deleteTask(task.id)
                                         confirmingDeleteTask = nil
                                     },
                                     onCancel: { confirmingDeleteTask = nil })
                    // the time stays where it always is; inert while confirming
                    // (no tap-to-edit / scrub until the confirm resolves).
                    totalView(task, active: active, interactive: false)
                }
            } else if isEditing(.editTotal(task.id)) {
                // typing the total: the field + its ✓/✕ own the row's tail,
                // so the total label steps aside for a clean edit line.
                HStack(spacing: 6) {
                    playStop(task, active: active)
                    taskName(task)
                    Spacer(minLength: 6)
                    totalField(task)
                }
            } else {
                // the total stays the last IN-FLOW element (flush right, fixed
                // position); the delete xmark, while hovered, is inserted IN FLOW
                // right before it — it eats into the flexible spacer instead of
                // overlaying the time, so the time never moves and is never
                // covered, and a non-hovered row reserves no width at all.
                HStack(spacing: 6) {
                    playStop(task, active: active)
                    taskName(task)
                    Spacer(minLength: 6)
                    // A favourite, marked by the card's switch — neutral tokens,
                    // no coloured frame.
                    if task.important {
                        StarGlyph(color: Theme.textSecondary, box: 10)
                    }
                    // "there is something inside" — the row's only hint that the
                    // card holds a comment. Inert: the row itself opens the card.
                    if !task.note.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if showsHoverX, hovered == task.id {
                        HoverDeleteX { confirmingDeleteTask = task.id }
                    }
                    totalView(task, active: active)
                }
            }
        }
        // No explicit frame needed: normal/confirm are pinned to 22pt by
        // playStop's fixed 22pt gutter, and nameField/totalField (see below)
        // are sized to the same 22pt natural height — so all four branches
        // already agree, and this row matches to-dos' untouched 26pt exactly
        // (22pt content + this 2pt vertical padding × 2), with zero growth.
        .padding(.vertical, 2)
        .background(rowFrameReader(task.id))
        // whole-row drag surface: grabbing anywhere reorders (see dragGesture).
        // While the list scrolls (capped), the row gesture stands down
        // (`.subviews`) so the pan scrolls and the total-scrub/taps keep working.
        .contentShape(Rectangle())
        .onTapGesture { expandCard(task) }
        .gesture(dragGesture(task.id, isProject: false),
                 including: trackerCapped ? .subviews : .all)
        .opacity(dragTask == task.id ? 0.4 : 1)
        .offset(dragTask == task.id ? dragTranslation : .zero)
        .zIndex(dragTask == task.id ? 2 : 0)
        .onHover { inside in
            if inside { hovered = task.id } else if hovered == task.id { hovered = nil }
        }
    }

    // MARK: - A task's history

    /// The sessions the task collected, under its open card: every stretch of
    /// time it holds, each editable and removable, plus a line to add one that
    /// was never tracked (Anton, 2026-08-28). The total above them is the same
    /// number the row shows — that is the point of listing the parts.
    @ViewBuilder private func history(_ task: TrackerTask) -> some View {
        let entries = engine.history(taskID: task.id)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(t(.trackerHistory))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 6)
                Text(shortTime(engine.total(taskID: task.id)))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.bottom, 2)
            // A long-lived task can hold hundreds of sessions; the card shows
            // the recent ones and says how many it did not draw, rather than
            // turning the panel into a ledger.
            ForEach(entries.prefix(Self.historyLimit)) { entry in
                historyRow(task, entry)
            }
            if entries.count > Self.historyLimit {
                Text("+\(entries.count - Self.historyLimit)")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            if isEditing(.newEntry(task.id)) {
                entryField(commit: { seconds in
                    engine.addSession(taskID: task.id, seconds: seconds)
                })
            } else {
                Button { beginNewEntry(task) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                        Text(t(.trackerHistoryAdd)).font(Theme.mono(10))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(4, bleed: 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private func historyRow(_ task: TrackerTask, _ entry: TrackerHistoryEntry) -> some View {
        if isEditing(.editEntry(entry.id)) {
            entryField(commit: { seconds in engine.setEntryDuration(entry.id, to: seconds) })
        } else {
            HStack(spacing: 6) {
                Text(historyLabel(entry))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if hovered == entry.id {
                    HoverDeleteX { engine.deleteEntry(entry.id) }
                }
                Text(shortTime(abs(entry.seconds)))
                    .font(Theme.mono(10))
                    .foregroundStyle(entry.isRunning ? Theme.textPrimary : Theme.listText)
                    .monospacedDigit()
                    .fixedSize()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            // The running session has no end to edit yet — stopping it is how
            // you correct it, exactly as in the engine.
            .onTapGesture { if !entry.isRunning { beginEditEntry(entry) } }
            .onHover { inside in
                if inside { hovered = entry.id } else if hovered == entry.id { hovered = nil }
            }
        }
    }

    /// What one line says on its left: when the session ran, or that this is a
    /// by-hand adjustment and which day it was dated to. A minus sign carries
    /// the sign of a negative adjustment, since the figure itself is drawn
    /// unsigned.
    private func historyLabel(_ entry: TrackerHistoryEntry) -> String {
        switch entry.kind {
        case .session(let start, let running):
            let when = Self.historyMoment.string(from: start)
            return running ? "\(when) ·" : when
        case .adjustment(let day):
            let sign = entry.seconds < 0 ? "− " : ""
            return "\(sign)\(t(.trackerAdjustment)) · \(Self.historyDay.string(from: day))"
        }
    }

    private static let historyLimit = 8

    private static let historyMoment: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM j:mm")
        return formatter
    }()

    private static let historyDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    /// One field, used both for editing a line and for adding one: the same
    /// lenient H:MM:SS / H:MM / MM parse the row's own total edit uses.
    /// The field sits where the figure it replaces sits — flush RIGHT, on the
    /// column every duration lines up in — and carries the same filled
    /// background the row's own total edit uses, so it reads as a box to type
    /// in rather than a cursor floating beside two icons (Anton, 2026-08-28).
    private func entryField(commit: @escaping (TimeInterval) -> Void) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                TextField("", text: $totalDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 62)
                    .focused($focused, equals: activeField)
                    .onAppear { focused = activeField }
                    .onSubmit { commitEntry(commit) }
                    .onExitCommand { endEdit() }
                FieldCommitButtons(onCommit: { commitEntry(commit) }, onCancel: { endEdit() })
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 2)
    }

    private func commitEntry(_ commit: (TimeInterval) -> Void) {
        defer { endEdit() }
        guard let seconds = parseTotal(totalDraft) else { return }
        commit(seconds)
    }

    private func playStop(_ task: TrackerTask, active: Bool) -> some View {
        Button {
            // the engine stops the previously active task itself (single-active)
            active ? engine.stopActive() : engine.start(taskID: task.id)
        } label: {
            // same play/pause family as the main timer button: filled circle
            // offers "start" (play), bordered circle offers "pause". Scaled to
            // the task row.
            // one shared diameter with the to-do checkbox, left-aligned in the
            // 22pt leading gutter so its visible edge sits on the row inset line
            // (the same line the subheader/footer text start on) and the two
            // circles line up on the same left column.
            TransportCircle(systemName: active ? "pause.fill" : "play.fill", filled: !active)
                .frame(width: RowCircle.gutter, height: RowCircle.gutter, alignment: .leading)
        }
        .buttonStyle(.plain)
        .hoverDim()
        .help(t(active ? .tipStopTask : .tipStartTask))
    }

    /// Display-only: renaming happens in the card, which the row opens on a tap.
    /// A double click lands there too — one editing route, not two.
    private func taskName(_ task: TrackerTask) -> some View {
        Text(task.name)
            .font(Theme.mono(12))
            .foregroundStyle(Theme.listText)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Card lifecycle

    private func expandCard(_ task: TrackerTask) {
        guard !Snapshot.active, expandedTask != task.id else { return }
        endEdit()
        clearConfirms()
        card = TaskCardDraft(text: task.name, note: task.note, important: task.important)
        expandedTask = task.id
    }

    private func collapseCard() {
        expandedTask = nil
        card = nil
    }

    /// Writes the draft back through the engine's own mutators, each of which
    /// no-ops on an unchanged value, so an untouched field saves nothing.
    private func commitCard(_ task: TrackerTask) {
        guard let card else { return collapseCard() }
        let trimmed = card.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != task.name { engine.renameTask(task.id, to: trimmed) }
        engine.setNote(taskID: task.id, to: card.note)
        withAnimation(.easeInOut(duration: 0.22)) {
            engine.setImportant(taskID: task.id, card.important)
        }
        collapseCard()
    }

    // MARK: - 8-hour warning

    /// True while the active task's CURRENT open interval has been running for
    /// over 8 hours. Recomputed off `tracker.heartbeat`, so the row appears and
    /// disappears without any timer of its own (no repeatForever).
    private func isLongRun(_ taskID: UUID) -> Bool {
        guard engine.activeTaskID == taskID, let start = engine.activeIntervalStart else { return false }
        return Date().timeIntervalSince(start) > 8 * 3600
    }

    /// A gentle "forgot to stop?" row directly under the long-running task, with
    /// a small stop button. No system notification in this pass.
    private func longRunRow(_ taskID: UUID) -> some View {
        HStack(spacing: 6) {
            Text(t(.trackerLongRun))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.accentYellow)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button { engine.stopActive() } label: {
                TransportCircle(systemName: "stop.fill", filled: false, iconSize: 8)
            }
            .buttonStyle(.plain)
            .hoverDim()
            .help(t(.tipStopTask))
        }
        .padding(.vertical, 2)   // matches the task-row rhythm (to-dos parity)
        .padding(.leading, 30)   // sits under the task text, past the row inset + play gutter
        .padding(.trailing, 2)
    }

    // MARK: - Total value (emphasis while active; scrub/type while idle)

    // The editing branch lives in `taskRow` (it reshapes the whole row); this is
    // only the read/scrub/tap-to-edit label.
    @ViewBuilder private func totalView(_ task: TrackerTask, active: Bool, interactive: Bool = true) -> some View {
        let figure = engine.amount(taskID: task.id, period: period)
        let value = scrubbingTask == task.id ? (scrubPending ?? figure) : figure
        let label = Text(shortTime(value))
            .font(Theme.mono(11))
            .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
            .monospacedDigit()
            .fixedSize()
        if active || !interactive {
            // active task: the engine refuses edits, so no affordance is offered.
            // interactive == false: shown during a delete confirm — the time must
            // stay put but not react to taps/scrub until the confirm resolves.
            label
        } else {
            label
                .contentShape(Rectangle())
                .help(t(.trackerEditHint))
                .simultaneousGesture(TapGesture().onEnded { beginEditTotal(task) })
                .simultaneousGesture(totalScrub(task.id))
        }
    }

    private func totalField(_ task: TrackerTask) -> some View {
        HStack(spacing: 4) {
            TextField("", text: $totalDraft)
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 66)
                .focused($focused, equals: .editTotal(task.id))
                .onAppear { focused = .editTotal(task.id) }
                .onSubmit { commitTotal(task.id) }
                .onExitCommand { endEdit() }
            FieldCommitButtons(onCommit: { commitTotal(task.id) }, onCancel: { endEdit() })
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 4))
        // natural height: FieldCommitButtons' 18pt + this 2pt padding × 2 = 22pt,
        // matching nameField and the task row's untouched 22pt content budget.
    }

    /// Each 8pt of horizontal travel = ±1 minute, a tick per step; the running
    /// preview lives in `scrubPending` and commits as ONE correction on end.
    private func totalScrub(_ taskID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard engine.activeTaskID != taskID else { return }
                if scrubRejected { return }
                if scrubbingTask != taskID {
                    // a reorder already claimed this drag — never scrub on top of
                    // it. The reorder samples at a smaller minimumDistance (3 vs
                    // 4), so a drag that starts vertical can lift the row before
                    // this branch's first sample even looks at the axis; the axis
                    // test alone would then let a curving drag scrub too.
                    guard dragTask == nil else { scrubRejected = true; return }
                    // engage only when the drag is horizontally dominant; a
                    // vertical-dominant drag is a row reorder, so stand down.
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        scrubRejected = true
                        return
                    }
                    scrubbingTask = taskID
                    // the scrub edits whatever figure is on screen
                    scrubBase = engine.amount(taskID: taskID, period: period)
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
                    engine.set(taskID: taskID, period: period, to: pending)
                }
                resetScrub()
            }
    }

    private func resetScrub() {
        scrubbingTask = nil
        scrubBase = nil
        scrubPending = nil
        scrubSteps = 0
        scrubRejected = false
    }

    // MARK: - Drag to reorder

    /// The whole row is the drag surface — no reserved handle gutter. The reorder
    /// engages only when the drag's first move past the threshold is VERTICALLY
    /// dominant, so a horizontal drag on the total label falls through to its
    /// scrub (see `totalScrub`). Living on the row container, it leaves the
    /// play/stop button and the hover xmark their taps — a tap never crosses
    /// `minimumDistance`, so those child gestures win.
    private func dragGesture(_ id: UUID, isProject: Bool) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if dragRejected { return }
                if dragTask == nil {
                    // decide the axis on the first move: a horizontal-dominant
                    // drag is a total scrub, not a reorder — stand down.
                    guard abs(value.translation.height) > abs(value.translation.width) else {
                        dragRejected = true
                        return
                    }
                    dragTask = id

                    // a drag must not fight an open field, a pending confirm or
                    // an open card, whose own fields want the pointer
                    endEdit()
                    clearConfirms()
                    collapseCard()
                }
                dragTranslation = value.translation
                dropTarget = resolveDrop(id, isProject: isProject, at: value.location.y)
            }
            .onEnded { value in
                if dragTask == id {
                    commitDrop(id, isProject: isProject,
                               to: resolveDrop(id, isProject: isProject, at: value.location.y))
                }
                resetDrag()
            }
    }

    /// The measured rows, as `TrackerDrop` wants them.
    private func dropRows() -> [TrackerDrop.Row] {
        displayRows.compactMap { row in
            guard let frame = rowFrames[row.id] else { return nil }
            return TrackerDrop.Row(id: row.id, parent: row.parent,
                                   isProject: row.project != nil,
                                   isExpanded: row.project?.isExpanded ?? false,
                                   midY: frame.midY)
        }
    }

    /// Where the pointer says the row lands — parent and index both, clamped
    /// into the dragged task's importance group when the float setting is on
    /// (the clamp only ever applies within one parent, which is the level the
    /// group lives on).
    private func resolveDrop(_ id: UUID, isProject: Bool, at y: CGFloat) -> TrackerDrop.Target {
        let target = TrackerDrop.target(rows: dropRows(), dragging: id,
                                        isProject: isProject, at: y)
        guard importantOnTop, !isProject else { return target }
        let siblings = target.parent.map { engine.tasks(in: $0) }
            ?? engine.topLevel.compactMap { item -> TrackerTask? in
                if case .task(let task) = item { return task } else { return nil }
            }
        let clamped = TrackerDisplay.clampedInsertion(siblings, dragging: id,
                                                      rawInsertion: target.index,
                                                      importantFirst: true)
        return TrackerDrop.Target(parent: target.parent, index: clamped)
    }

    private func commitDrop(_ id: UUID, isProject: Bool, to target: TrackerDrop.Target) {
        if isProject {
            guard let from = engine.data.rootOrder.firstIndex(of: id) else { return }
            engine.moveRootItem(from: from, to: target.index)
            return
        }
        let task = engine.data.tasks.first { $0.id == id }
        // staying under the same parent is a reorder; changing parent is a move
        if task?.projectID == target.parent {
            if let parent = target.parent,
               let from = engine.tasks(in: parent).firstIndex(where: { $0.id == id }) {
                engine.moveTaskInProject(parent, from: from, to: target.index)
            } else if let from = engine.data.rootOrder.firstIndex(of: id) {
                engine.moveRootItem(from: from, to: target.index)
            }
        } else {
            engine.moveTask(id, toProject: target.parent, at: target.index)
        }
    }

    private func resetDrag() {
        dragTask = nil

        dragTranslation = .zero
        dropTarget = nil
        dragRejected = false
    }

    /// The y at which to draw the drop indicator line for a resolved target:
    /// between the rows that will end up around it, among the target's own
    /// siblings.
    private func indicatorY(for target: TrackerDrop.Target) -> CGFloat? {
        let siblings = dropRows()
            .filter { $0.id != dragTask && $0.parent != dragTask && $0.parent == target.parent }
            .map(\.id)
        // an empty project shows the line under its own header
        guard !siblings.isEmpty else {
            return target.parent.flatMap { rowFrames[$0]?.maxY }
        }
        if target.index <= 0 { return rowFrames[siblings.first!]?.minY }
        if target.index >= siblings.count { return rowFrames[siblings.last!]?.maxY }
        if let a = rowFrames[siblings[target.index - 1]]?.maxY,
           let b = rowFrames[siblings[target.index]]?.minY { return (a + b) / 2 }
        return rowFrames[siblings[target.index]]?.minY
    }

    @ViewBuilder private var dropIndicatorOverlay: some View {
        if let target = dropTarget, let y = indicatorY(for: target) {
            Rectangle()
                .fill(Theme.editing)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                // a line inside a project starts where the project's contents do
                .padding(.leading, target.parent == nil ? 0 : Self.projectIndent)
                .offset(y: y - 1)
                .allowsHitTesting(false)
        }
    }

    private func rowFrameReader(_ id: UUID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: RowFrameKey.self,
                                   value: [id: geo.frame(in: .named(Self.listSpace))])
        }
    }

    // MARK: - Add affordance

    /// Two ways to add, on one line: a task goes to the top level, a project
    /// starts a group. Side by side rather than stacked — the panel cannot
    /// spare a second 26pt row for something used once in a while.
    @ViewBuilder private var addRows: some View {
        if isEditing(.newTask) {
            // nameField's own natural height is 22pt (sized to match the task
            // row's content budget — see its definition below); the footer has
            // no outer-padding wrapper to add the rest, so pin it to 26pt here,
            // matching addRowLabel's 26pt below it exactly.
            nameField(.newTask, placeholder: t(.trackerNewTask))
                .frame(height: 26)
        } else if isEditing(.newProject) {
            nameField(.newProject, placeholder: t(.trackerNewProject))
                .frame(height: 26)
        } else {
            // Two ways to add on one line, but not two labels crowding the
            // left: the project one is pushed out to the RIGHT, onto the column
            // the times line up in, so it reads as belonging to the list rather
            // than trailing the task button (Anton, 2026-08-28).
            HStack(spacing: 10) {
                Button { beginNewTask() } label: {
                    addRowLabel(t(.trackerNewTask), iconSize: 10)
                }
                .buttonStyle(.plain)
                .hoverHighlight(6, bleed: 5)
                Spacer(minLength: 6)
                Button { beginNewProject() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                        Text(t(.trackerNewProject)).font(Theme.mono(11))
                    }
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 5)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(6, bleed: 5)
            }
        }
    }

    private func addRowLabel(_ text: String, iconSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: iconSize, weight: .semibold))
            Text(text).font(Theme.mono(11))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(.vertical, 5)
        // pinned to 26pt to match the footer's editing state exactly (see
        // addTaskRow) — content alone is ~13pt, well clear of the 26pt floor.
        .frame(height: 26)
        .contentShape(Rectangle())
    }

    // MARK: - Shared pieces

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
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
        // FieldCommitButtons' 18pt icon buttons + this 2pt vertical padding × 2
        // land at 22pt naturally — the task row's untouched content budget
        // (playStop's 22pt gutter), so the rename branch never grows the row.
        // The footer (addTaskRow) pins its own instance up to 26pt separately.
    }

    // MARK: - Edit lifecycle

    private func beginNewTask() {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = ""
        activeField = .newTask
    }

    private func beginEditEntry(_ entry: TrackerHistoryEntry) {
        guard !Snapshot.active else { return }
        clearConfirms()
        totalDraft = draftText(for: abs(entry.seconds))
        activeField = .editEntry(entry.id)
    }

    private func beginNewEntry(_ task: TrackerTask) {
        guard !Snapshot.active else { return }
        clearConfirms()
        totalDraft = ""
        activeField = .newEntry(task.id)
    }

    private func beginNewTaskIn(_ projectID: UUID) {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = ""
        activeField = .newTaskIn(projectID)
    }

    private func beginNewProject() {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = ""
        activeField = .newProject
    }

    /// A tap on a project's row renames it — projects have no card, and the
    /// fold is the chevron's own job, so the row itself is free for this.
    private func beginRenameProject(_ project: TrackerProject) {
        guard !Snapshot.active else { return }
        endEdit()
        clearConfirms()
        collapseCard()
        nameDraft = project.name
        activeField = .renameProject(project.id)
    }

    /// A duration written the way the field's own parser reads it back
    /// (H:MM:SS / H:MM / MM), so opening an edit and pressing return changes
    /// nothing.
    private func draftText(for seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if s > 0 { return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))" }
        return h > 0 ? "\(h):\(String(format: "%02d", m))" : "\(m)"
    }

    private func beginEditTotal(_ task: TrackerTask) {
        guard !Snapshot.active, engine.activeTaskID != task.id else { return }
        clearConfirms()
        totalDraft = draftText(for: engine.amount(taskID: task.id, period: period))
        activeField = .editTotal(task.id)
    }

    private func commitName() {
        defer { endEdit() }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }   // empty input = cancel
        switch activeField {
        case .newTask: engine.addTask(name: name)
        case .newTaskIn(let projectID): engine.addTask(name: name, projectID: projectID)
        case .newProject: engine.addProject(name: name)
        case .renameProject(let projectID): engine.renameProject(projectID, to: name)
        default: break
        }
    }

    private func commitTotal(_ taskID: UUID) {
        defer { endEdit() }
        guard let seconds = parseTotal(totalDraft) else { return }
        engine.set(taskID: taskID, period: period, to: seconds)
    }

    private func endEdit() {
        activeField = nil
        focused = nil
        nameDraft = ""
        totalDraft = ""
    }

    private func clearConfirms() {
        confirmingDeleteTask = nil
        confirmingDeleteProject = nil
    }

    /// Lenient parse of the total field. `1` number = minutes, `2` = `H:MM`,
    /// `3` = `H:MM:SS`. Returns nil for empty or unparseable input (= cancel).
    private func parseTotal(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 1:
            guard let m = Int(parts[0]) else { return nil }
            return TimeInterval(m * 60)
        case 2:
            guard let h = Int(parts[0]) else { return nil }
            let m = Int(parts[1]) ?? 0
            return TimeInterval(h * 3600 + m * 60)
        case 3:
            guard let h = Int(parts[0]) else { return nil }
            let m = Int(parts[1]) ?? 0
            let s = Int(parts[2]) ?? 0
            return TimeInterval(h * 3600 + m * 60 + s)
        default:
            return nil
        }
    }
}
