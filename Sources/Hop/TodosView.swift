import SwiftUI
import HopCore

/// To-do module: a flat checklist. Rows are a hover drag-handle + circle
/// checkbox + text; a footer row opens an inline field to add a new item at the
/// bottom. Deletion is a hover xmark with NO confirmation — a to-do is cheap to
/// lose and cheap to retype. Rows share the tracker's leading gutter (2pt inset
/// + 14pt handle + 6pt spacing) and row rhythm, so the two modules line up when
/// stacked on the same space. Theme tokens only.
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
    // Which row's trailing xmark / drag handle is revealed.
    @State private var hovered: UUID?

    // Drag-to-reorder: a handle at each row's left edge lifts an item; the drop
    // resolves against measured row frames. One move per completed drag.
    @State private var dragItem: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dropIndex: Int?
    @State private var rowFrames: [UUID: CGRect] = [:]

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        let items = todos.list.items
        return VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                // Name the feature above the hint: an otherwise bare "nothing to
                // do yet" says nothing about what this space is.
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(.todosLabel))
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Text(t(.todosEmpty))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            ForEach(items) { row($0) }
            addRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: Self.listSpace)
        .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
        .overlay(alignment: .topLeading) { dropIndicatorOverlay }
        .onChange(of: adding) { _, on in onEditingChanged?(on && !Snapshot.active) }
        .onDisappear {
            // @State survives the popover hide/show — a left-open field would
            // reappear (unfocused) on the next open, so clear it here.
            endAdd()
            resetDrag()
        }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 6) {
            dragHandle(item.id)
            Button { todos.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(item.done ? Theme.textTertiary : Theme.textSecondary)
                    .frame(width: 22, height: 22)
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
            Spacer(minLength: 6)
            HoverDeleteX(visible: hovered == item.id) { todos.delete(item.id) }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
        .background(rowFrameReader(item.id))
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(6)
        }
    }

    // MARK: - Drag to reorder

    /// A burger handle at the row's left edge — same pattern and gutter as the
    /// tracker, so the checkbox lines up with the tracker's play button.
    private func dragHandle(_ id: UUID) -> some View {
        let shown = hovered == id || dragItem == id
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .frame(width: 14, height: 18)
            .contentShape(Rectangle())
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .gesture(dragGesture(id))
    }

    private func dragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if dragItem == nil {
                    dragItem = id
                    endAdd()   // a drag must not fight an open add field
                }
                dragTranslation = value.translation
                dropIndex = resolveDrop(at: value.location.y)
            }
            .onEnded { value in
                commitDrop(id, resolveDrop(at: value.location.y))
                resetDrag()
            }
    }

    /// Resolves a pointer y to an insertion index among the OTHER items — the
    /// index `TodoList.move` inserts at after lifting the dragged item out.
    private func resolveDrop(at y: CGFloat) -> Int {
        let others = todos.list.items.map(\.id).filter { $0 != dragItem }
        return others.filter { (rowFrames[$0]?.midY ?? .greatestFiniteMagnitude) < y }.count
    }

    private func commitDrop(_ id: UUID, _ toIndex: Int?) {
        guard let toIndex, let from = todos.list.items.firstIndex(where: { $0.id == id }) else { return }
        todos.move(from: from, to: toIndex)
    }

    private func resetDrag() {
        dragItem = nil
        dragTranslation = .zero
        dropIndex = nil
    }

    private func indicatorY(for toIndex: Int) -> CGFloat? {
        let ids = todos.list.items.map(\.id).filter { $0 != dragItem }
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
        draft = ""
        adding = true
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
