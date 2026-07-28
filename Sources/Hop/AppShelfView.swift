import HopCore
import SwiftUI
import UniformTypeIdentifiers

/// One grid of apps: eight across, up to eight rows.
///
/// Behaves the way a home screen does, because that is the behaviour everyone
/// already knows: drag an icon and the others shuffle around it; hold the mouse
/// down and the whole grid starts to wobble, which is when a ✕ appears on each
/// icon; drop an app from Finder anywhere on the grid to park it.
struct AppShelfView: View {
    @ObservedObject var shelves: AppShelvesController
    let shelfID: UUID
    let lang: AppLanguage

    /// The icon being dragged, and where it would land.
    @State private var dragging: UUID?
    @State private var dropIndex: Int?
    /// Wobble mode: reached by holding the mouse on the grid, left by clicking
    /// anywhere outside an icon.
    @State private var editing = false
    @State private var wobble = false
    @State private var isTargeted = false

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    private var shelf: AppShelf? { shelves.shelves[shelfID] }

    /// 8 columns, fixed — the row is the unit here, not the panel's width.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6),
                                count: AppShelf.columns)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            subheader
            if let shelf {
                if shelf.items.isEmpty {
                    empty
                } else {
                    grid(shelf)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A drop anywhere on the module parks the app; Finder hands over a file URL.
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.editing, lineWidth: 1)
                .opacity(isTargeted ? 1 : 0)
        )
        .onDisappear { editing = false; wobble = false }
    }

    private var subheader: some View {
        HStack(spacing: 6) {
            Text(t(.appsLabel))
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            if editing {
                // Says what the wobble means and how to leave it, since a wobbling
                // grid is a mode and a mode needs a way out.
                Text(t(.appsEditingHint))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                Button(t(.appsDone)) { stopEditing() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .hoverDim()
            }
        }
        .padding(.horizontal, 2)
    }

    private var empty: some View {
        Text(t(.appsEmpty))
            .font(Theme.mono(11))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
    }

    private func grid(_ shelf: AppShelf) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                cell(item, at: index)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }

    private func cell(_ item: ShelfItem, at index: Int) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: shelves.icon(for: item))
                .resizable()
                .frame(width: 30, height: 30)
                .overlay(alignment: .topLeading) {
                    if editing {
                        Button { shelves.remove(item.id, from: shelfID) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textPrimary, Theme.rowBg)
                        }
                        .buttonStyle(.plain)
                        .offset(x: -4, y: -4)
                    }
                }
            Text(item.name)
                .font(Theme.mono(8))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .opacity(dragging == item.id ? 0.35 : 1)
        // The wobble: a small finite rotation back and forth. Deliberately driven
        // by a repeating animation ONLY while editing, and stopped on exit — the
        // panel must not resize itself forever.
        .rotationEffect(.degrees(editing && wobble ? 1.4 : editing ? -1.4 : 0))
        .animation(editing
                   ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true)
                   : .default, value: wobble)
        .contentShape(Rectangle())
        .onTapGesture {
            if editing { return }   // in wobble mode a tap is not a launch
            shelves.launch(item, from: shelfID)
        }
        .onLongPressGesture(minimumDuration: 0.6) { startEditing() }
        .gesture(dragGesture(item, at: index))
        .help(item.name)
    }

    /// Dragging an icon reorders the grid. The drop index is worked out from how
    /// far the pointer travelled in cells, which keeps the maths independent of
    /// the panel's width.
    private func dragGesture(_ item: ShelfItem, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragging = item.id
                dropIndex = destination(from: index, translation: value.translation)
            }
            .onEnded { _ in
                if let dropIndex { shelves.move(item.id, to: dropIndex, in: shelfID) }
                dragging = nil
                self.dropIndex = nil
            }
    }

    /// Cell geometry: 36pt wide, 44pt tall including the label — close enough
    /// that a drag lands where the pointer is.
    private func destination(from index: Int, translation: CGSize) -> Int {
        let across = Int((translation.width / 36).rounded())
        let down = Int((translation.height / 44).rounded())
        let count = shelf?.items.count ?? 0
        return max(0, min(index + across + down * AppShelf.columns, max(0, count - 1)))
    }

    private func startEditing() {
        guard !Snapshot.active, !editing else { return }
        editing = true
        wobble = true
    }

    private func stopEditing() {
        editing = false
        wobble = false
    }

    /// Finder hands over file URLs; anything that is not an app is ignored.
    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in shelves.add(path: url.path, to: shelfID) }
            }
        }
    }
}
