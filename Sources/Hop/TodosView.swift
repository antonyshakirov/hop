import SwiftUI
import HopCore

/// To-do module: a flat checklist. Rows are a circle checkbox + text, flush left
/// (the checkbox is the leading element, lined up with the tracker's play button
/// on the same left column); a footer row opens an inline field to add a new item
/// at the bottom. Deletion is a hover xmark that switches the row into an in-row
/// confirm (delete/cancel) rather than deleting on the spot — the checkbox and
/// text stay put, only the trailing ✕ swaps for the two buttons, so the row keeps
/// its silhouette. A `to-dos` subheader names the module above
/// the list. Rows use a tight rhythm (spacing 3, vertical padding 2) that the
/// tracker now matches exactly, so the near-twin modules read identically;
/// reorder is a whole-row vertical drag. Theme tokens only.
struct TodosView: View {
    @ObservedObject var todos: TodosController
    let lang: AppLanguage
    /// Fired when the add field opens (true) / closes (false) so the panel can
    /// hold the keyboard while typing — otherwise keystrokes leak to the app
    /// underneath and digits could drive the timer if it shares this space.
    var onEditingChanged: ((Bool) -> Void)? = nil

    private struct RowFrameKey: PreferenceKey {
        static let defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { $1 })
        }
    }

    private static let listSpace = "todosList"

    @State private var adding = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    // Which row's trailing xmark is revealed (hover-only).
    @State private var hovered: UUID?
    // Which row is in delete-confirm mode (single: a new confirm closes any other).
    @State private var confirmingDelete: UUID?
    // Which row is expanded into its card, and the draft it is editing. One card
    // at a time: opening another closes this one, so the panel cannot grow without
    // bound and there is never a question of which edit a commit belongs to.
    @State private var expanded: UUID?
    @State private var card: TaskCardDraft?
    // Rows with an unacknowledged firing blink three times on the first open.
    @State private var blinkPhase = false
    @State private var blinking = false

    // Drag-to-reorder: a vertical drag anywhere on a row lifts an item; the drop
    // resolves against measured row frames. One move per completed drag.
    @State private var dragItem: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dropIndex: Int?
    @State private var rowFrames: [UUID: CGRect] = [:]
    // Latched when a drag's first move is horizontal-dominant, so an off-axis
    // swipe doesn't lift a row (reorder is vertical).
    @State private var dragRejected = false

    /// "visible rows" cap: 0 = all (default), 3…15 caps the list to a fixed height
    /// with inner scroll.
    @AppStorage(TodosController.visibleRowsKey) private var visibleRows = TodosController.defaultVisibleRows
    /// Float important tasks to the top of the list. OFF by default: marking a
    /// task important is a mark, and moving it is a separate decision.
    @AppStorage(SettingsKey.todoImportantOnTop) private var importantOnTop = false

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    /// True when the list overflows an active cap and therefore scrolls. While it
    /// scrolls the whole-row reorder drag stands down (the pan drives the scroll
    /// instead) — reorder is for the short, fully-visible list.
    private var capped: Bool {
        !Snapshot.active && RowCap.scrolls(stored: visibleRows, count: todos.list.displayItems.count)
    }

    /// Display order, honouring the importance setting. A snapshot renders the
    /// plain order so screenshots never depend on a preference.
    private var displayItems: [TodoItem] {
        todos.list.displayItems(importantFirst: importantOnTop && !Snapshot.active)
    }

    /// Finite reorder animation for the sink-to-bottom (and the return trip).
    /// No repeatForever — infinite animations retrigger the panel's size
    /// recompute and jitter the popover.
    private static let sinkAnimation: Animation = .easeInOut(duration: 0.22)

    var body: some View {
        // Display order: active items (stored order) first, then completed items
        // (stored order). Completing an item sinks it to the bottom pile WITHOUT
        // touching the stored order, so unchecking returns it to its slot.
        let items = displayItems
        return VStack(alignment: .leading, spacing: 3) {
            // An empty list shows only the subheader and the add row — the
            // subheader already names the module, so no placeholder line.
            subheader
            // The subheader and the add row stay OUTSIDE the scroll (always
            // visible); only the item list scrolls between them, at exactly
            // cap rows plus their gaps — 29·cap − 3 (integral, no height jump).
            if capped, let height = RowCap.listHeight(stored: visibleRows, count: items.count) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) { ForEach(items) { row($0) } }
                }
                .frame(height: height)
            } else {
                ForEach(items) { row($0) }
            }
            addRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: Self.listSpace)
        .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
        .overlay(alignment: .topLeading) { dropIndicatorOverlay }
        .onChange(of: adding) { _, on in onEditingChanged?(on && !Snapshot.active) }
        .onChange(of: expanded) { _, id in onEditingChanged?(id != nil && !Snapshot.active) }
        .onAppear {
            // The panel is open, so anything that fired while it was closed has
            // now been seen: blink the times three times, then clear the mark.
            todos.reconcile()
            acknowledgeWithBlink()
        }
        // A reminder that fires WHILE the panel is open has to blink too — on
        // appear it did not exist yet.
        .onChange(of: todos.list.hasUnseenFiring) { _, unseen in
            if unseen { acknowledgeWithBlink() }
        }
        .onDisappear {
            // @State survives the popover hide/show — a left-open field, a pending
            // confirm or an open card would reappear on the next open, so clear
            // all three here.
            endAdd()
            clearConfirms()
            collapseCard()
            resetDrag()
        }
    }

    /// Three seconds of slow yellow pulsing on the fired time, then the firing
    /// counts as seen and the menu-bar mark goes with it.
    ///
    /// Six half-second fades rather than a few sharp flashes: one quick blink was
    /// over before the eye found it (Anton, 2026-07-28). Finite by construction —
    /// a repeatForever animation retriggers the panel's size recompute and
    /// jitters the popover.
    private func acknowledgeWithBlink() {
        guard !Snapshot.active, todos.list.hasUnseenFiring else { return }
        guard !blinking else { return }   // a second trigger must not stack blinks
        blinking = true
        blinkPhase = false
        let fade = 0.5
        for phase in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + fade * Double(phase)) {
                withAnimation(.easeInOut(duration: fade)) { blinkPhase = phase % 2 == 0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade * 6) {
            withAnimation(.easeInOut(duration: fade)) { blinkPhase = false }
            blinking = false
            todos.acknowledgeFirings()
        }
    }

    /// A compact module sublabel above the list — same treatment as the settings
    /// section headers (mono 10 semibold, tertiary, lowercase), so the to-do and
    /// tracker lists are distinguishable at a glance when stacked on one space.
    private var subheader: some View {
        Text(t(.todosLabel))
            .font(Theme.mono(10, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 2)
    }

    @ViewBuilder private func row(_ item: TodoItem) -> some View {
        if expanded == item.id, card != nil, !Snapshot.active {
            TaskCardView(draft: Binding(get: { card ?? TaskCardDraft(text: item.text,
                                                                    note: item.note,
                                                                    important: item.important) },
                                        set: { card = $0 }),
                         lang: lang,
                         onCommit: { commitCard(item) },
                         onCancel: { collapseCard() })
                .padding(.horizontal, 2)
                .background(rowFrameReader(item.id))
        } else {
            collapsedRow(item)
        }
    }

    private func collapsedRow(_ item: TodoItem) -> some View {
        HStack(spacing: 6) {
            Button { withAnimation(Self.sinkAnimation) { todos.toggle(item.id) } } label: {
                // same circle family and diameter as the tracker's play/stop, in
                // muted tokens: an empty ring when open, a filled disc with a
                // knocked-out check when done. Left-aligned in the shared 22pt
                // gutter so its visible edge sits on the row inset line (the same
                // line the subheader/footer text start on) and the two modules
                // line up on the same left column.
                TransportCircle(systemName: item.done ? "checkmark" : "",
                                filled: item.done,
                                diameter: RowCircle.checkboxDiameter,
                                iconSize: 10,
                                fillColor: Theme.textTertiary,
                                strokeColor: Theme.textSecondary,
                                glyphColor: Theme.background)
                    .frame(width: RowCircle.gutter, height: RowCircle.gutter, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
            Text(item.text)
                .font(Theme.mono(12))
                .foregroundStyle(item.done ? Theme.textTertiary : Theme.listText)
                .strikethrough(item.done, color: Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            // the Spacer keeps the row full-width (drag surface); the hover
            // xmark, when shown, sits IN FLOW right after it, so a non-hovered
            // row has no reserved gap, hovering never shifts anything, and a
            // long already-truncated text yields room to the xmark instead of
            // running under it (a trailing overlay could not guarantee that).
            Spacer(minLength: 6)
            // A favourite: the star is the mark, set by the card's switch. Drawn
            // in neutral tokens — a coloured frame read as a warning rather than
            // "this one matters" (Anton, 2026-07-28).
            if item.important {
                StarGlyph(color: Theme.textSecondary, box: 10)
            }
            // "there is something inside" — the collapsed row's only hint that
            // the card holds a comment. Inert: the whole row opens the card.
            if !item.note.isEmpty {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
            if let firing = RemindSchedule.effectiveFiring(item) {
                // A time in the past means it already fired: struck through, so a
                // banner that went unseen still leaves a trace in the list.
                //
                // While it is still unacknowledged the time BLINKS BLUE — the same
                // blue as the menu-bar dot that brought you here, so the panel
                // answers "which task was it?" the moment you open it. The dot
                // leaves with the blink and the struck-through time stays.
                let lit = item.firedUnseen && blinkPhase
                Text(Self.timeLabel.string(from: firing))
                    .font(Theme.mono(11))
                    .foregroundStyle(lit ? Theme.accentYellow : Theme.textTertiary)
                    // The strike line keeps ONE colour through the blink: changing
                    // it rebuilt the attributed text every phase and the line
                    // visibly jumped (Anton, 2026-07-28).
                    .strikethrough(firing <= Date(), color: Theme.textTertiary)
            }
            if confirmingDelete == item.id {
                // confirm swaps in for the ✕ only — the checkbox and text keep
                // their place, so the row's silhouette and height don't change.
                RowDeleteConfirm(lang: lang,
                                 onDelete: {
                                     todos.delete(item.id)
                                     confirmingDelete = nil
                                 },
                                 onCancel: { confirmingDelete = nil })
            } else if hovered == item.id {
                HoverDeleteX { confirmingDelete = item.id }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(rowFrameReader(item.id))
        // whole-row drag surface: grabbing anywhere reorders (see dragGesture).
        // While the list scrolls (capped), the row gesture stands down
        // (`.subviews`) so the pan scrolls and the checkbox/xmark keep their taps.
        .contentShape(Rectangle())
        .onTapGesture { expandCard(item) }
        .gesture(dragGesture(item.id), including: capped ? .subviews : .all)
        .opacity(dragItem == item.id ? 0.4 : 1)
        .offset(dragItem == item.id ? dragTranslation : .zero)
        .zIndex(dragItem == item.id ? 2 : 0)
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
    }

    /// The row's reminder time, in the user's own clock format.
    private static let timeLabel: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter
    }()

    @ViewBuilder private var addRow: some View {
        if adding, !Snapshot.active {
            HStack(spacing: 8) {
                TextField(t(.todosNew), text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($fieldFocused)
                    .onAppear { fieldFocused = true }
                    .onSubmit { commit() }
                    .onExitCommand { endAdd() }
                FieldCommitButtons(onCommit: { commit() }, onCancel: { endAdd() })
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
            // FieldCommitButtons' 18pt icon buttons + this 3pt vertical padding
            // × 2 come to 24pt, so the explicit 26pt pin does the work — matching
            // the button branch below exactly (see that branch's comment).
            .frame(height: 26)
        } else {
            Button { beginAdd() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text(t(.todosNew)).font(Theme.mono(11))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
                // matches the editing branch's 26pt above — otherwise the
                // footer row jumps by a few px on open/close of the add field.
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(6)
        }
    }

    // MARK: - Drag to reorder

    /// The whole row is the drag surface — no reserved handle gutter. The reorder
    /// engages only on a VERTICALLY dominant drag, so an off-axis swipe leaves the
    /// row put. Living on the row container, it leaves the checkbox and the hover
    /// xmark their taps — a tap never crosses `minimumDistance`, so those child
    /// gestures win.
    private func dragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if dragRejected { return }
                if dragItem == nil {
                    // decide the axis on the first move: only a vertical-dominant
                    // drag reorders; anything else is left alone.
                    guard abs(value.translation.height) > abs(value.translation.width) else {
                        dragRejected = true
                        return
                    }
                    dragItem = id
                    endAdd()         // a drag must not fight an open add field
                    clearConfirms()  // …or a pending delete confirm
                    collapseCard()   // …or an open card, whose fields own the pointer
                }
                dragTranslation = value.translation
                // clamp the insertion into the dragged item's group, so the
                // indicator line stops at a group boundary (active/completed, and
                // important/ordinary while that setting is on)
                dropIndex = TodoDisplay.clampedInsertion(
                    todos.list.items, dragging: id, rawInsertion: resolveDrop(at: value.location.y),
                    importantFirst: importantOnTop)
            }
            .onEnded { value in
                if dragItem == id { commitDrop(id, resolveDrop(at: value.location.y)) }
                resetDrag()
            }
    }

    /// Resolves a pointer y to an insertion index among the OTHER items — the
    /// index `TodoList.move` inserts at after lifting the dragged item out.
    private func resolveDrop(at y: CGFloat) -> Int {
        let others = todos.list.items.map(\.id).filter { $0 != dragItem }
        return others.filter { (rowFrames[$0]?.midY ?? .greatestFiniteMagnitude) < y }.count
    }

    private func commitDrop(_ id: UUID, _ toDisplayIndex: Int?) {
        guard let toDisplayIndex else { return }
        // reorder clamps to the item's group internally; animate the settle
        withAnimation(Self.sinkAnimation) {
            todos.reorder(dragging: id, toDisplayInsertion: toDisplayIndex,
                          importantFirst: importantOnTop)
        }
    }

    private func resetDrag() {
        dragItem = nil
        dragTranslation = .zero
        dropIndex = nil
        dragRejected = false
    }

    private func indicatorY(for toIndex: Int) -> CGFloat? {
        // toIndex is a DISPLAY-order insertion index (rows are laid out in display
        // order), so resolve the line against the display-order ids.
        let ids = TodoDisplay.order(todos.list.items, importantFirst: importantOnTop)
            .map(\.id).filter { $0 != dragItem }
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

    // MARK: - Add lifecycle

    private func beginAdd() {
        guard !Snapshot.active else { return }
        clearConfirms()   // opening the add field drops any pending confirm
        draft = ""
        adding = true
    }

    private func clearConfirms() {
        confirmingDelete = nil
    }

    // MARK: - Card lifecycle

    /// Opens the card for a row, seeding its draft from what is stored. Opening
    /// one card closes any other — and any pending confirm or add field, which
    /// would otherwise compete for the same keyboard.
    private func expandCard(_ item: TodoItem) {
        guard !Snapshot.active else { return }
        guard expanded != item.id else { return }
        endAdd()
        clearConfirms()
        card = TaskCardDraft(text: item.text, note: item.note, important: item.important,
                             reminder: ReminderDraft(date: item.remindAt,
                                                     repeatDays: item.repeatDays))
        expanded = item.id
    }

    private func collapseCard() {
        expanded = nil
        card = nil
    }

    /// Writes the draft back. Each field goes through its own mutator, so an
    /// unchanged one costs nothing, and a cleared date removes the reminder
    /// outright rather than leaving a half-armed one behind.
    private func commitCard(_ item: TodoItem) {
        guard let card else { return collapseCard() }
        todos.setText(item.id, to: card.text)
        todos.setNote(item.id, to: card.note)
        withAnimation(Self.sinkAnimation) { todos.setImportant(item.id, card.important) }
        if let date = card.reminder?.date {
            todos.setReminder(item.id, at: date, repeatDays: card.reminder?.repeatDays ?? [])
        } else if item.remindAt != nil {
            todos.clearReminder(item.id)
        }
        collapseCard()
    }

    private func commit() {
        todos.add(text: draft)   // empty input trims to nothing = no-op
        endAdd()
    }

    private func endAdd() {
        adding = false
        fieldFocused = false
        draft = ""
    }
}
