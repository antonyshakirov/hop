import SwiftUI
import HopCore

/// Time-tracker module: a flat list of tasks with play/stop and an all-time
/// total per row (ticking while active), inline rename and total-editing (scrub
/// or type), whole-row drag to reorder, and an 8-hour "still tracking" warning
/// under a long-running task. Projects are gone — `rootOrder` is the single
/// source of the list's order. All state lives in the engine (single-active
/// invariant, aggregates, corrections); this view is glue. Visual language
/// follows TorrentView's rows — Theme tokens only, no infinite animations.
/// Labels tick off `tracker.heartbeat` while running.
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
        case renameTask(UUID)
        case editTotal(UUID)        // taskID
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

    // Drag-to-reorder: a vertical drag anywhere on a row lifts a task; the drop
    // resolves against measured row frames. One engine move per completed drag.
    // A horizontal-dominant drag is left to the total label's scrub (axis gate).
    @State private var dragTask: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dropIndex: Int?
    @State private var rowFrames: [UUID: CGRect] = [:]
    // Latched when a reorder drag's first move is horizontal-dominant — that's a
    // total scrub, so this row-reorder gesture stands down for the rest of it.
    @State private var dragRejected = false

    private var engine: TrackerEngine { tracker.engine }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private func shortTime(_ v: TimeInterval) -> String { TimeFormatting.short(v) }

    /// A field is only "editing" outside snapshots — keeps yellow TextField
    /// artifacts out of `--snapshot` renders.
    private func isEditing(_ field: Field) -> Bool {
        !Snapshot.active && activeField == field
    }

    var body: some View {
        // read the heartbeat so every label (and the 8h warning) recomputes
        // while a task is tracking
        let _ = tracker.heartbeat
        let rootIDs = engine.data.rootOrder
        let taskByID = Dictionary(engine.data.tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 6) {
            subheader
            if rootIDs.isEmpty {
                // The subheader already names the module, so the empty state is
                // just the hint — no duplicate title line.
                Text(t(.trackerEmpty))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
            }
            ForEach(rootIDs, id: \.self) { id in
                if let task = taskByID[id] {
                    taskRow(task)
                    if isLongRun(task.id) { longRunRow(task.id) }
                }
            }
            addTaskRow
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

    // MARK: - Module subheader

    /// A compact module sublabel above the list — same treatment as the settings
    /// section headers (mono 10 semibold, tertiary, lowercase), so the tracker
    /// and to-do lists are distinguishable at a glance when stacked on one space.
    private var subheader: some View {
        Text(t(.trackerLabel))
            .font(Theme.mono(10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 2)
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
            } else if isEditing(.renameTask(task.id)) {
                nameField(.renameTask(task.id), placeholder: task.name)
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
                HStack(spacing: 6) {
                    playStop(task, active: active)
                    taskName(task)
                    Spacer(minLength: 6)
                    totalView(task, active: active)
                    HoverDeleteX(visible: hovered == task.id) { confirmingDeleteTask = task.id }
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .background(rowFrameReader(task.id))
        // whole-row drag surface: grabbing anywhere reorders (see dragGesture)
        .contentShape(Rectangle())
        .gesture(dragGesture(task.id))
        .opacity(dragTask == task.id ? 0.4 : 1)
        .offset(dragTask == task.id ? dragTranslation : .zero)
        .zIndex(dragTask == task.id ? 2 : 0)
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
                TransportCircle(systemName: "stop.fill", filled: false, diameter: 20, iconSize: 8)
            }
            .buttonStyle(.plain)
            .hoverDim()
        }
        .padding(.vertical, 3)
        .padding(.leading, 30)   // sits under the task text, past the row inset + play gutter
        .padding(.trailing, 2)
    }

    // MARK: - Total value (emphasis while active; scrub/type while idle)

    // The editing branch lives in `taskRow` (it reshapes the whole row); this is
    // only the read/scrub/tap-to-edit label.
    @ViewBuilder private func totalView(_ task: TrackerTask, active: Bool) -> some View {
        let value = (scrubbingTask == task.id ? (scrubPending ?? engine.total(taskID: task.id))
                                              : engine.total(taskID: task.id))
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
    }

    /// Each 8pt of horizontal travel = ±1 minute, a tick per step; the running
    /// preview lives in `scrubPending` and commits as ONE correction on end.
    private func totalScrub(_ taskID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard engine.activeTaskID != taskID else { return }
                if scrubRejected { return }
                if scrubbingTask != taskID {
                    // engage only when the drag is horizontally dominant; a
                    // vertical-dominant drag is a row reorder, so stand down.
                    guard abs(value.translation.width) > abs(value.translation.height) else {
                        scrubRejected = true
                        return
                    }
                    scrubbingTask = taskID
                    scrubBase = engine.total(taskID: taskID)
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
                    engine.setTotal(taskID: taskID, to: pending)
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
    private func dragGesture(_ id: UUID) -> some Gesture {
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
                    // a drag must not fight an open field or a pending confirm
                    endEdit()
                    clearConfirms()
                }
                dragTranslation = value.translation
                dropIndex = resolveDrop(at: value.location.y)
            }
            .onEnded { value in
                if dragTask == id { commitDrop(id, resolveDrop(at: value.location.y)) }
                resetDrag()
            }
    }

    /// Resolves a pointer y (in list space) to an insertion index among the
    /// OTHER tasks — exactly the index `moveRootItem` inserts at after lifting
    /// the dragged task out.
    private func resolveDrop(at y: CGFloat) -> Int {
        let others = engine.data.rootOrder.filter { $0 != dragTask }
        return others.filter { (rowFrames[$0]?.midY ?? .greatestFiniteMagnitude) < y }.count
    }

    private func commitDrop(_ id: UUID, _ toIndex: Int?) {
        guard let toIndex, let from = engine.data.rootOrder.firstIndex(of: id) else { return }
        engine.moveRootItem(from: from, to: toIndex)
    }

    private func resetDrag() {
        dragTask = nil
        dragTranslation = .zero
        dropIndex = nil
        dragRejected = false
    }

    /// The y at which to draw the drop indicator line for the resolved index.
    private func indicatorY(for toIndex: Int) -> CGFloat? {
        let ids = engine.data.rootOrder.filter { $0 != dragTask }
        if ids.isEmpty { return nil }
        if toIndex <= 0 { return rowFrames[ids.first!]?.minY }
        if toIndex >= ids.count { return rowFrames[ids.last!]?.maxY }
        if let a = rowFrames[ids[toIndex - 1]]?.maxY, let b = rowFrames[ids[toIndex]]?.minY { return (a + b) / 2 }
        return rowFrames[ids[toIndex]]?.minY
    }

    @ViewBuilder private var dropIndicatorOverlay: some View {
        if let idx = dropIndex, let y = indicatorY(for: idx) {
            Rectangle()
                .fill(Theme.editing)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
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

    @ViewBuilder private var addTaskRow: some View {
        if isEditing(.newTask) {
            nameField(.newTask, placeholder: t(.trackerNewTask))
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
        } else {
            Button { beginNewTask() } label: {
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

    private func beginNewTask() {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = ""
        activeField = .newTask
    }

    private func beginRenameTask(_ task: TrackerTask) {
        guard !Snapshot.active else { return }
        clearConfirms()
        nameDraft = task.name
        activeField = .renameTask(task.id)
    }

    private func beginEditTotal(_ task: TrackerTask) {
        guard !Snapshot.active, engine.activeTaskID != task.id else { return }
        clearConfirms()
        let total = Int(engine.total(taskID: task.id))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        // prefill in a shape the parser reads back (H:MM:SS / H:MM / MM)
        totalDraft = s > 0 ? "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
                   : (h > 0 ? "\(h):\(String(format: "%02d", m))" : "\(m)")
        activeField = .editTotal(task.id)
    }

    private func commitName() {
        defer { endEdit() }
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }   // empty input = cancel
        switch activeField {
        case .newTask: engine.addTask(name: name)
        case .renameTask(let id): engine.renameTask(id, to: name)
        default: break
        }
    }

    private func commitTotal(_ taskID: UUID) {
        defer { endEdit() }
        guard let seconds = parseTotal(totalDraft) else { return }
        engine.setTotal(taskID: taskID, to: seconds)
    }

    private func endEdit() {
        activeField = nil
        focused = nil
        nameDraft = ""
        totalDraft = ""
    }

    private func clearConfirms() {
        confirmingDeleteTask = nil
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
