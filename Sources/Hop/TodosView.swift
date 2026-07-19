import SwiftUI
import HopCore

/// To-do module: a flat checklist. Rows are a circle checkbox + text; a footer
/// row opens an inline field to add a new item at the bottom. Deletion is a
/// hover xmark with NO confirmation — a to-do is cheap to lose and cheap to
/// retype. Flat rows in the tracker/torrent visual language, Theme tokens only.
struct TodosView: View {
    @ObservedObject var todos: TodosController
    let lang: AppLanguage
    /// Fired when the add field opens (true) / closes (false) so the panel can
    /// hold the keyboard while typing — otherwise keystrokes leak to the app
    /// underneath and digits could drive the timer if it shares this space.
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var adding = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    // Which row's trailing xmark is revealed.
    @State private var hovered: UUID?

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        let items = todos.list.items
        return VStack(alignment: .leading, spacing: 4) {
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
        .onChange(of: adding) { _, on in onEditingChanged?(on && !Snapshot.active) }
        .onDisappear {
            // @State survives the popover hide/show — a left-open field would
            // reappear (unfocused) on the next open, so clear it here.
            endAdd()
        }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Button { todos.toggle(item.id) } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(item.done ? Theme.textTertiary : Theme.textSecondary)
                    .frame(width: 20, height: 20)
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
