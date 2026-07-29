import AppKit
import HopCore
import SwiftUI
import UniformTypeIdentifiers

/// One grid of apps: eight across, up to eight rows.
///
/// Behaves the way a home screen does, because that is the behaviour everyone
/// already knows: drag an icon and a yellow line shows which two it lands between; the
/// edit button starts the wobble, which is when a ✕ appears on each icon; apps
/// arrive either from the + or dropped in from Finder.
///
/// A grid carries its own name and decides whether the names under the icons are
/// drawn at all, because several grids on one space have to be told apart and a
/// wall of bare icons is what some people want.
struct AppShelfView: View {
    @ObservedObject var shelves: AppShelvesController
    let shelfID: UUID
    let lang: AppLanguage

    /// The icon being dragged, where it started, how far it has travelled, and
    /// where it would land.
    @State private var dragging: UUID?
    @State private var dragOrigin: Int?
    @State private var dragOffset: CGSize = .zero
    @State private var dropIndex: Int?
    /// Wobble mode: entered from the edit button, left by "done".
    @State private var editing = false
    @State private var wobblePhase = false
    @State private var wobbleTimer: Timer?
    @State private var isTargeted = false
    /// The name being typed. Kept apart from the stored one so a field that is
    /// mid-word does not fight the model on every keystroke.
    @State private var draftTitle = ""

    /// How the wobble runs. Slow and wide reads as a swaying icon; fast and
    /// narrow reads as a flicker, which is what the first attempt looked like.
    private static let wobbleAngle = 1.8
    private static let wobbleStep = 0.36

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    private var shelf: AppShelf? { shelves.shelves[shelfID] }

    private var showsLabels: Bool { shelf?.showsLabels ?? true }

    private var displayTitle: String {
        let title = shelf?.title.trimmingCharacters(in: .whitespaces) ?? ""
        return title.isEmpty ? t(.appsLabel) : title
    }

    /// The icon's own size. A slot is exactly this wide, so the spacers between
    /// slots are the only thing between two icons.
    /// 32, up from 30 (Anton, 2026-07-30). Nine of them across the module leave a
    /// 6.5pt gap: bigger icons AND one more per row, with the gaps small enough
    /// that the eye stops comparing them. 34 would leave 4.25pt, which reads as
    /// icons touching.
    private static let iconSize: CGFloat = 32
    /// Measured width of one row — the pitch and the drag maths come from it.
    @State private var rowWidth: CGFloat = 0

    /// Distance from one icon's left edge to the next one's. Eight icons flush
    /// against both module edges leave seven EQUAL gaps. A LazyVGrid could not do
    /// that: centring every cell indented the row by half the column's slack, and
    /// aligning only the outer two to the edges made the outer gaps 3.6pt wider
    /// than the inner ones (Anton, 2026-07-30).
    private var pitch: CGFloat {
        guard rowWidth > Self.iconSize else { return Self.iconSize + 14 }
        return (rowWidth - Self.iconSize) / CGFloat(AppShelf.columns - 1)
    }

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
            if editing {
                // Says what the wobble means, below the grid rather than in the
                // header, which is busy with the name while editing.
                Text(t(.appsEditingHint))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A drop anywhere on the module parks the app; Finder hands over a file
        // URL. Snapshot-aware: ImageRenderer draws a raw onDrop as a yellow block.
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Theme.editing, lineWidth: 1)
                .opacity(isTargeted ? 1 : 0)
        )
        .onAppear { draftTitle = shelf?.title ?? "" }
        .onDisappear { stopEditing() }
    }

    // MARK: - Header

    private var subheader: some View {
        HStack(spacing: 6) {
            if editing {
                // A bare line of text does not read as a field: it needs a box, a
                // pencil and a placeholder that ASKS for something (Anton,
                // 2026-07-30 — "name" sitting there read as a column heading).
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(t(.appsNamePlaceholder), text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .onChange(of: draftTitle) { _, new in
                            shelves.setTitle(new, for: shelfID)
                        }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
                .frame(maxWidth: 132)
                .help(t(.appsNamePlaceholder))
                Spacer(minLength: 0)
                Button(t(.appsDone)) { stopEditing() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .hoverDim()
            } else {
                Text(displayTitle)
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Both affordances are always on screen: the first build hid
                // adding behind a Finder drag and editing behind a long press,
                // and neither was found.
                headerButton("plus", help: t(.appsAddApp)) { shelves.promptToAdd(to: shelfID) }
                    .disabled(shelf?.isFull ?? false)
                headerButton("slider.horizontal.3", help: t(.appsEditGrid)) { startEditing() }
            }
        }
    }

    private func headerButton(_ symbol: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .help(help)
    }

    private var empty: some View {
        Text(t(.appsEmpty))
            .font(Theme.mono(11))
            .foregroundStyle(Theme.textTertiary)
            .padding(.vertical, 6)
    }

    // MARK: - Grid

    private func grid(_ shelf: AppShelf) -> some View {
        let rows = stride(from: 0, to: shelf.items.count, by: AppShelf.columns).map { start in
            Array(shelf.items[start..<min(start + AppShelf.columns, shelf.items.count)])
        }
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(0..<AppShelf.columns, id: \.self) { column in
                        if column > 0 { Spacer(minLength: 0) }
                        if column < row.count {
                            cell(row[column], at: rowIndex * AppShelf.columns + column)
                        } else {
                            // holds the pitch of a half-filled last row
                            Color.clear.frame(width: Self.iconSize, height: 1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { rowWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, width in rowWidth = width }
        })
    }

    private func cell(_ item: ShelfItem, at index: Int) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: shelves.icon(for: item))
                .resizable()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .overlay(alignment: .topLeading) { deleteBadge(item) }
            if showsLabels {
                Text(item.name)
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        // The first icon sits ON the module's left line and the last on its right
        // one; only the ones between are centred in their column. Centring every
        // cell left the row indented by half the slack (the icon is 30pt in a
        // ~37pt column), so the icons stood further in than every label and row
        // above them (Anton, 2026-07-29).
        // Exactly one icon wide: the spacers between slots carry all the slack,
        // so every gap is the same and the outer icons sit on the module's own
        // left and right lines.
        .frame(width: Self.iconSize)
        .padding(.vertical, 2)
        // The gap the dragged icon would drop into, on whichever side of this
        // cell it falls.
        .overlay(alignment: .leading) { insertionLine(at: index, on: .leading) }
        .overlay(alignment: .trailing) { insertionLine(at: index, on: .trailing) }
        // The wobble: neighbouring icons lean opposite ways, the way a home
        // screen does, so the grid sways instead of pulsing in lockstep. Driven
        // by a timer rather than a repeatForever animation, which makes the
        // hosting controller recompute its size forever.
        .rotationEffect(.degrees(wobbleAngle(at: index)))
        .animation(.easeInOut(duration: Self.wobbleStep), value: wobblePhase)
        .animation(.easeInOut(duration: Self.wobbleStep), value: editing)
        // The dragged icon follows the pointer and rides above the rest.
        .scaleEffect(dragging == item.id ? 1.08 : 1)
        .offset(dragging == item.id ? dragOffset : .zero)
        .zIndex(dragging == item.id ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            if editing { return }   // in wobble mode a tap is not a launch
            shelves.launch(item, from: shelfID)
        }
        .gesture(dragGesture(item, at: index))
        .help(item.name)
    }

    /// The ✕ that removes an icon. Muted on purpose: a bright badge on a moving
    /// icon reads as blinking.
    @ViewBuilder private func deleteBadge(_ item: ShelfItem) -> some View {
        if editing {
            Button { shelves.remove(item.id, from: shelfID) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.background, Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .offset(x: -3, y: -3)
            .help(t(.appsRemoveApp))
        }
    }

    private enum CellEdge { case leading, trailing }

    /// The yellow line: the GAP the icon drops into, not the icon it lands on.
    /// Highlighting the target cell read as "swap with this one" (Anton,
    /// 2026-07-29); a line between two icons says where it goes.
    ///
    /// Which gap that is depends on the direction: dragging an icon forward
    /// pulls everything after it one place back, so it ends up AFTER the cell at
    /// the drop index; dragging it backwards puts it BEFORE that cell.
    @ViewBuilder private func insertionLine(at index: Int, on edge: CellEdge) -> some View {
        if insertionEdge(at: index) == edge {
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.editing)
                .frame(width: 2)
                .padding(.vertical, 1)
                // Half the grid's 6pt column gap, so the line sits in the space
                // between two icons rather than on top of either.
                .offset(x: edge == .leading ? -3 : 3)
        }
    }

    private func insertionEdge(at index: Int) -> CellEdge? {
        guard let dropIndex, let dragOrigin,
              dropIndex != dragOrigin, dropIndex == index else { return nil }
        return dropIndex > dragOrigin ? .trailing : .leading
    }

    private func wobbleAngle(at index: Int) -> Double {
        guard editing else { return 0 }
        let leaning = (index % 2 == 0) == wobblePhase
        return leaning ? Self.wobbleAngle : -Self.wobbleAngle
    }

    // MARK: - Dragging

    /// Dragging an icon reorders the grid. The drop index is worked out from how
    /// far the pointer travelled in cells, which keeps the maths independent of
    /// the panel's width.
    private func dragGesture(_ item: ShelfItem, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragging = item.id
                dragOrigin = index
                dragOffset = value.translation
                dropIndex = destination(from: index, translation: value.translation)
            }
            .onEnded { _ in
                if let dropIndex { shelves.move(item.id, to: dropIndex, in: shelfID) }
                dragging = nil
                dragOrigin = nil
                dragOffset = .zero
                self.dropIndex = nil
            }
    }

    /// Cell geometry: the measured pitch across, 44pt down with the names on and
    /// 36pt without —
    /// close enough that a drag lands where the pointer is.
    private func destination(from index: Int, translation: CGSize) -> Int {
        let rowHeight: CGFloat = showsLabels ? Self.iconSize + 14 : Self.iconSize + 6
        let across = Int((translation.width / pitch).rounded())
        let down = Int((translation.height / rowHeight).rounded())
        let count = shelf?.items.count ?? 0
        return max(0, min(index + across + down * AppShelf.columns, max(0, count - 1)))
    }

    // MARK: - Edit mode

    private func startEditing() {
        guard !Snapshot.active, !editing else { return }
        draftTitle = shelf?.title ?? ""
        editing = true
        wobblePhase = true
        wobbleTimer?.invalidate()
        wobbleTimer = Timer.scheduledTimer(withTimeInterval: Self.wobbleStep, repeats: true) { _ in
            Task { @MainActor in wobblePhase.toggle() }
        }
    }

    private func stopEditing() {
        wobbleTimer?.invalidate()
        wobbleTimer = nil
        editing = false
        wobblePhase = false
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
