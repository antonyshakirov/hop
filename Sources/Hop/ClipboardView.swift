import AppKit
import SwiftUI

/// Clipboard tab: recently copied texts; clicking a row puts it back
/// on the clipboard (the row keeps its position).
struct ClipboardView: View {
    @ObservedObject var clipboard: ClipboardController
    let lang: AppLanguage
    var closePanel: () -> Void = {}
    /// Fired when the search field gains (true) / loses (false) focus, so the
    /// panel holds the keyboard while typing a query — otherwise the panel's
    /// global ⌘V would feed the converter and digits could drive the timer,
    /// same reason the tracker/to-do fields surface their editing state.
    var onSearchFocusChanged: ((Bool) -> Void)? = nil

    @State private var copiedId: UUID?
    @State private var expanded = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    // collapsed — the user-chosen number of rows (1...10, default 3);
    // expanded — up to 20, BUT with a height ceiling:
    // the panel must fit under the menu bar, otherwise the NSPopover doesn't fit
    // and drifts to the screen edge ("panel on the right", buttons unreachable).
    // The ceiling is DYNAMIC — screen height minus headroom for the other
    // modules: a fixed 430 broke as soon as more modules were added.
    // The tail of the list is reached via inner scrolling. Do NOT remove the ceiling!
    /// Entries filtered by search (search only exists in the expanded state).
    private var filteredItems: [ClipboardController.Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard expanded, !q.isEmpty else { return clipboard.items }
        return clipboard.items.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    /// How many ROWS are visible without scrolling (list window height);
    /// all entries remain reachable by scrolling even when collapsed.
    @AppStorage(ClipboardController.visibleRowsKey) private var visibleRows = ClipboardController.defaultVisibleRows
    private var visibleCount: Int {
        // collapsed shows the user-chosen number of rows (1...10, default 3);
        // the rest is always reachable by scrolling inside the fixed height
        expanded ? min(filteredItems.count, 20) : min(filteredItems.count, max(1, min(visibleRows, 10)))
    }
    private var expandedCeiling: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        // 560 — conservative headroom for the header and the other visible modules
        return max(208, min(430, screen - 560))
    }
    private var height: CGFloat {
        let searchRow: CGFloat = expanded ? 40 : 0 // 32 field + spacing
        let content = CGFloat(max(visibleCount, 1)) * 36 + 28 + searchRow
        return expanded ? min(expandedCeiling, content) : content
    }
    private var canExpand: Bool { clipboard.items.count > visibleCount }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 10))
                    Text(L10n.t(.tabClipboard, lang))
                        .font(Theme.mono(10))
                }
                .foregroundStyle(Theme.textTertiary)
                if canExpand {
                    // expand — on the left, next to the title; clear — on the opposite edge
                    Button {
                        expanded.toggle() // the panel grows downward without intermediate jumps
                    } label: {
                        // swap via opacity ONLY; geometryGroup detaches the icon
                        // from the layout animation — without it the panel height
                        // recalculation dragged the arrow away from its spot
                        ZStack {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .opacity(expanded ? 0 : 1)
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .opacity(expanded ? 1 : 0)
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .animation(.easeInOut(duration: 0.2), value: expanded)
                        .frame(width: 20, height: 18)
                        .geometryGroup()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(4)
                }
                Spacer()
                if !clipboard.items.isEmpty {
                    Button {
                        clipboard.clear()
                    } label: {
                        Text(L10n.t(.clipboardClear, lang))
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(4)
                }
            }
            if expanded {
                // search only in the expanded state: the collapsed clipboard is already in view
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                    TextField(L10n.t(.searchLabel, lang), text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textPrimary)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 32) // same as a clipboard row
                .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 5))
            }
            if clipboard.items.isEmpty {
                Text(L10n.t(.clipboardEmpty, lang))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxHeight: .infinity)
            } else if Snapshot.active {
                // snapshots: ImageRenderer can't render ScrollView —
                // draw the visible rows as a flat stack
                VStack(spacing: 4) {
                    ForEach(filteredItems.prefix(visibleCount)) { item in
                        itemRow(item)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        // render the FULL history: scrolling to old entries
                        // works even when collapsed — expanding merely
                        // shows more rows at once
                        ForEach(filteredItems) { item in
                            itemRow(item)
                        }
                    }
                }
            }
        }
        .frame(height: height, alignment: .top)
        .onChange(of: clipboard.items.count) { _, count in
            if count <= visibleCount { expanded = false }
        }
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded {
                query = ""
                searchFocused = false
            }
        }
        // Surface the field focus the same way the tracker/to-do fields do, so
        // the panel keeps the keyboard and its ⌘V doesn't hijack search paste.
        // Snapshots never carry live focus.
        .onChange(of: searchFocused) { _, focused in
            onSearchFocusChanged?(focused && !Snapshot.active)
        }
        // @State survives the popover hide/show and this view is torn down on a
        // space switch — report "not focused" so a stale focus can't linger in
        // the panel's editing gate after the clipboard leaves the space.
        .onDisappear { onSearchFocusChanged?(false) }
    }

    private func itemRow(_ item: ClipboardController.Item) -> some View {
        let isCopied = copiedId == item.id
        return HStack(spacing: 4) {
            Button {
                clipboard.copy(item)
                markCopied(item)
            } label: {
                HStack(spacing: 6) {
                    // file entries lead with a small doc glyph, image entries with
                    // a thumbnail; both leave the label (a file name / dimensions)
                    if item.filePaths != nil {
                        Image(systemName: "doc")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 16)
                    } else if let file = item.imageFile, let thumb = ClipThumbCache.image(file) {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(oneLine(item.text))
                        .font(Theme.mono(10))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                // text truncates a bit earlier — the icons need breathing room
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ClipboardRowStyle(isCopied: isCopied))

            // swap without changing geometry: the icons and the "copied" mark live
            // in one fixed-height layer — the row doesn't twitch
            ZStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    rowIcon("doc.on.doc") {
                        clipboard.copy(item)
                        markCopied(item)
                    }
                    rowIcon("text.insert") {
                        markCopied(item)
                        clipboard.copyAndPaste(item, closePanel: closePanel)
                    }
                }
                .opacity(isCopied ? 0 : 1)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accentGreen)
                    .opacity(isCopied ? 1 : 0)
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isCopied)
    }

    private func rowIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
    }

    private func markCopied(_ item: ClipboardController.Item) {
        copiedId = item.id
        Task {
            try? await Task.sleep(for: .seconds(1))
            if copiedId == item.id { copiedId = nil }
        }
    }

    private func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Highlights the text instantly on press (isPressed), without waiting for release.
private struct ClipboardRowStyle: ButtonStyle {
    let isCopied: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                configuration.isPressed || isCopied ? Theme.textPrimary : Theme.listText
            )
    }
}

/// Downscaled thumbnails for image entries: the stored PNGs are full-size
/// screenshots, decoding them per render would chew memory and CPU.
@MainActor
enum ClipThumbCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ file: String) -> NSImage? {
        if let cached = cache.object(forKey: file as NSString) { return cached }
        let url = ClipboardController.imagesDir.appendingPathComponent(file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 80,
              ] as CFDictionary)
        else { return nil }
        let thumb = NSImage(cgImage: cg, size: .zero)
        cache.setObject(thumb, forKey: file as NSString)
        return thumb
    }
}
