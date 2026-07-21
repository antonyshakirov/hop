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

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    /// True when the list overflows an active cap and therefore scrolls. While it
    /// scrolls the whole-row reorder drag stands down (the pan drives the scroll
    /// instead) — reorder is for the short, fully-visible list.
    private var capped: Bool {
        !Snapshot.active && RowCap.scrolls(stored: visibleRows, count: todos.list.displayItems.count)
    }

    /// Finite reorder animation for the sink-to-bottom (and the return trip).
    /// No repeatForever — infinite animations retrigger the panel's size
    /// recompute and jitter the popover.
    private static let sinkAnimation: Animation = .easeInOut(duration: 0.22)

    var body: some View {
        // Display order: active items (stored order) first, then completed items
        // (stored order). Completing an item sinks it to the bottom pile WITHOUT
        // touching the stored order, so unchecking returns it to its slot.
        let items = todos.list.displayItems
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
        .onDisappear {
            // @State survives the popover hide/show — a left-open field or a
            // pending confirm would reappear on the next open, so clear both here.
            endAdd()
            clearConfirms()
            resetDrag()
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

    private func row(_ item: TodoItem) -> some View {
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
        .gesture(dragGesture(item.id), including: capped ? .subviews : .all)
        .opacity(dragItem == item.id ? 0.4 : 1)
        .offset(dragItem == item.id ? dragTranslation : .zero)
        .zIndex(dragItem == item.id ? 2 : 0)
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
    }

    @ViewBuilder private var addRow: some View {
        if adding, !Snapshot.active {
            HStack(spacing: 4) {
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
            .padding(.horizontal, 6)
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
                    endAdd()        // a drag must not fight an open add field
                    clearConfirms() // …or a pending delete confirm
                }
                dragTranslation = value.translation
                // clamp the insertion into the dragged item's group, so the
                // indicator line stops at the active/completed boundary
                dropIndex = TodoDisplay.clampedInsertion(
                    todos.list.items, dragging: id, rawInsertion: resolveDrop(at: value.location.y))
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
            todos.reorder(dragging: id, toDisplayInsertion: toDisplayIndex)
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
        let ids = TodoDisplay.order(todos.list.items).map(\.id).filter { $0 != dragItem }
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
