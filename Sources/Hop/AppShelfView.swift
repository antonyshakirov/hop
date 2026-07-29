import AppKit
import HopCore
import SwiftUI
import UniformTypeIdentifiers

/// One grid of apps: eight across, up to eight rows.
///
/// Behaves the way a home screen does, because that is the behaviour everyone
/// already knows: drag an icon and a yellow slot shows where it will land; the
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
            if editing {
                // Says what the wobble means, below the grid rather than in the
                // header, which is busy with the name while editing.
                Text(t(.appsEditingHint))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
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
        .onAppear { draftTitle = shelf?.title ?? "" }
        .onDisappear { stopEditing() }
    }

    // MARK: - Header

    private var subheader: some View {
        HStack(spacing: 6) {
            if editing {
                TextField(t(.appsNamePlaceholder), text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: 110)
                    .onChange(of: draftTitle) { _, new in
                        shelves.setTitle(new, for: shelfID)
                    }
                Spacer(minLength: 0)
                labelsToggle
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

    /// Names under the icons, on or off. An icon, not the word "names": beside a
    /// field holding the grid's own name, that word read as the same thing twice
    /// (Anton, 2026-07-29). The tooltip says what it does.
    private var labelsToggle: some View {
        Button { shelves.setShowsLabels(!showsLabels, for: shelfID) } label: {
            Image(systemName: "textformat")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(showsLabels ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 20, height: 16)
                .background(showsLabels ? Theme.chipBg : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .help(t(.appsShowNames))
    }

    private var empty: some View {
        Text(t(.appsEmpty))
            .font(Theme.mono(11))
            .foregroundStyle(Theme.textTertiary)
            .padding(.vertical, 6)
    }

    // MARK: - Grid

    private func grid(_ shelf: AppShelf) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                cell(item, at: index)
            }
        }
        .padding(.vertical, 2)
    }

    private func cell(_ item: ShelfItem, at index: Int) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: shelves.icon(for: item))
                .resizable()
                .frame(width: 30, height: 30)
                .overlay(alignment: .topLeading) { deleteBadge(item) }
            if showsLabels {
                Text(item.name)
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity)
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

    /// Cell geometry: 36pt wide, 44pt tall with the names on and 36pt without —
    /// close enough that a drag lands where the pointer is.
    private func destination(from index: Int, translation: CGSize) -> Int {
        let rowHeight: CGFloat = showsLabels ? 44 : 36
        let across = Int((translation.width / 36).rounded())
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
