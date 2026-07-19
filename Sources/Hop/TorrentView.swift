import AppKit
import CoreServices
import SwiftUI
import UniformTypeIdentifiers
import HopCore

/// Torrent module: engine-install call-to-action, an empty add-card (pick a
/// .torrent or paste a magnet), and the active list of torrents as compact
/// two-line rows. Matches the panel patterns of ClipboardView (height-capped
/// inner scroll) and convertZone (drop target). Theme tokens only; no
/// repeatForever animations.
struct TorrentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var torrent: TorrentController
    let lang: AppLanguage

    /// Module-level fold (the whole list collapses to just the header). Distinct
    /// from the retired per-row expand; persisted so it survives panel reopens.
    @AppStorage("torrentCollapsed") private var torrentCollapsed = false

    /// One-time first-run offer to become the default `.torrent` handler.
    /// Flips true either way (accept or dismiss) — "later" only hides the
    /// banner, the same offer stays reachable from settings (torrentMakeDefault).
    @AppStorage("torrentDefaultHandlerPrompted") private var defaultHandlerPrompted = false

    @State private var confirmingRemove: String?
    @State private var dropTargeted = false

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    private var engineInstalled: Bool {
        if case .installed = torrent.installer.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 8) {
            if engineInstalled && !defaultHandlerPrompted {
                defaultHandlerBanner
            }
            Group {
                if !torrent.torrents.isEmpty {
                    activeList
                } else {
                    switch torrent.installer.state {
                    case .installed:
                        emptyZone
                    case .downloading(let progress):
                        engineStatusRow("\(t(.torrentGetting)) · \(engineSizeText) · \(Int(progress * 100))%")
                    case .verifying:
                        engineStatusRow(t(.torrentVerifying))
                    case .notInstalled, .failed:
                        enableRow
                    }
                }
            }
        }
    }

    // MARK: - First-run: offer to become the default .torrent handler

    /// Inline banner (Hop style, never a system alert), shown once right after
    /// the engine installs. A top row above the list/empty card. The question
    /// gets its own line (wraps rather than truncates — the 368pt panel is too
    /// narrow for some languages to fit next to two buttons on one line).
    private var defaultHandlerBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t(.torrentDefaultAsk))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Spacer()
                Button {
                    makeHopDefaultForTorrent()
                    defaultHandlerPrompted = true
                } label: {
                    HoverLabel(text: t(.torrentDefaultDo), size: 10, weight: .semibold, color: Theme.textPrimary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button {
                    defaultHandlerPrompted = true
                } label: {
                    HoverLabel(text: t(.torrentDefaultLater), size: 10, color: Theme.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
    }

    /// Register this bundle as the default handler for `.torrent` documents and
    /// `magnet:` links. Mirrors PanelView's settings-screen offer (kept local, not
    /// shared, so this file's only new import is CoreServices — no cross-file
    /// coupling). Once Hop owns the type, Finder shows Hop's icon on .torrent files.
    private func makeHopDefaultForTorrent() {
        let bundleID = Bundle.storageIdentifier
        LSSetDefaultRoleHandlerForContentType(
            "org.bittorrent.torrent" as CFString, .all, bundleID as CFString)
        LSSetDefaultHandlerForURLScheme("magnet" as CFString, bundleID as CFString)
    }

    // MARK: - Engine not installed

    private var enableRow: some View {
        Button {
            // Kicks the installer state machine (download → verify → install).
            // Fails closed until the signed engine is hosted, so this is a
            // harmless no-op today; the progress states above render once it is.
            Task { await torrent.installer.install() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(t(.torrentEnable))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .hoverHighlight(7)
    }

    /// Small-fetch reassurance shown next to the download percent. Uses the
    /// installer's manifest size with the app's decimal byte formatter; falls
    /// back to a rough estimate before the manifest is decoded.
    private var engineSizeText: String {
        let bytes = torrent.installer.engineSizeBytes
        return bytes > 0 ? SizeFormatting.sizeText(bytes) : "~25 MB"
    }

    /// Non-interactive status while the engine downloads or verifies.
    private func engineStatusRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - Empty (installed): one context-aware add button (drop bonus)

    private var emptyZone: some View {
        // One row, styled like the converter row: icon + label on the left, an
        // "open" arrow on the right. Tapping routes a magnet already on the
        // clipboard straight in, or opens the .torrent picker otherwise
        // (addTapped()). Drop stays a bonus — the popover hides on focus loss,
        // so drag-from-Finder is unreliable as the primary path.
        Button(action: addTapped) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(dropTargeted ? Theme.editing : Theme.textSecondary)
                Text("\(t(.torrentAdd)) · .torrent / magnet")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(dropTargeted ? Theme.editing : .clear, lineWidth: 1)
        )
        .hoverHighlight(7)
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task {
                for provider in providers {
                    guard let url = await loadFileURL(provider),
                          url.pathExtension.lowercased() == "torrent",
                          let data = try? Data(contentsOf: url) else { continue }
                    add(source: .file(data))
                }
            }
            return true
        }
    }

    // MARK: - Active list

    private var activeList: some View {
        VStack(spacing: 8) {
            header
            if !torrentCollapsed {
                // No animation: the list reveals/hides instantly so the header
                // never drifts (Hop's panel must not jump/twitch).
                listBody
            }
        }
    }

    /// Module header: the title in the bright primary color (matching the other
    /// module headers), the aggregate speeds secondary, a compact add (while
    /// downloading), and the module fold chevron.
    private var doneCount: Int { torrent.torrents.filter { $0.stats?.finished ?? false }.count }

    private var header: some View {
        HStack(spacing: 6) {
            // fold chevron on the LEFT: reads as "expand the section", away from
            // the ↓/↑ speed arrows.
            rowIcon(torrentCollapsed ? "chevron.right" : "chevron.down") {
                torrentCollapsed.toggle()
            }
            Text(t(.torrentLabel))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
            // glance stat: how many are done out of the total, without expanding.
            Text("· ✓ \(doneCount)/\(torrent.torrents.count)")
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .fixedSize()
            Spacer(minLength: 6)
            // labeled add, visually separate from the fold control. Same
            // context-aware behavior as the empty-state button (addTapped()).
            Button(action: addTapped) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                    Text(t(.torrentAdd)).font(Theme.mono(10))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.divider, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(5)
        }
    }

    /// No inner scroll: the torrent rows render inline and the whole panel is the
    /// single scroll (the panel caps its own height in StatusItemController). A
    /// per-module scroll here would nest inside the panel's — scroll-in-scroll,
    /// which Anton nixed.
    private var listBody: some View {
        VStack(spacing: 6) {
            ForEach(torrent.torrents) { row($0) }
        }
    }

    // MARK: - Row (two lines, no per-row expand)

    private func row(_ item: TorrentController.TorrentItem) -> some View {
        let stats = item.stats
        let pct = Int((stats?.fraction ?? 0) * 100)
        let finished = stats?.finished ?? false
        let paused = item.optimisticPaused ?? (item.pausedByPolicy || stats?.state == .paused)
        let errored = stats?.state == .error
        // The download glyph lights up only while bytes are ACTUALLY flowing
        // (Anton, 2026-07-18): white when live and receiving, gray when paused,
        // stalled (no peers) or not started yet — the color answers "is it
        // downloading right now?" at a glance.
        let downloadingNow = !paused && !finished && !errored && !item.filesMissing
            && stats?.state == .live && (stats?.downloadBps ?? 0) > 0
        return VStack(spacing: 4) {
            // Line 1: status glyph, name, tight action cluster.
            HStack(spacing: 6) {
                if confirmingRemove == item.id {
                    // Confirm takes the whole line — full width for clear options.
                    removeConfirm(item)
                } else {
                    Image(systemName: item.filesMissing ? "folder.badge.questionmark"
                                    : (errored ? "exclamationmark.triangle.fill"
                                    : (finished ? "checkmark.circle.fill" : "arrow.down.circle")))
                        .font(.system(size: 12))
                        .foregroundStyle(item.filesMissing || errored ? Theme.accentRed
                                       : (finished ? Theme.accentGreen
                                       : (downloadingNow ? Theme.textPrimary : Theme.textSecondary)))
                    Text(shortName(item.name))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.listText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    HStack(spacing: 0) {
                        // Multi-file torrents expand into a per-file list (toggle each
                        // file's download, watch per-file progress). Single-file rows
                        // have nothing to unfold, so the chevron is theirs only.
                        if item.files.count > 1 {
                            rowIcon(torrent.expandedIds.contains(item.id) ? "chevron.up" : "chevron.down") {
                                torrent.toggleExpanded(item.id)   // instant, no animation — the panel must not drift
                            }
                        }
                        // Pause/resume is available in EVERY state: while downloading it
                        // stops/resumes the download; when finished it stops/resumes
                        // SEEDING (previously the only way to stop seeding was remove or
                        // the ratio-1.0 policy — a real UX gap).
                        rowIcon(paused ? "play.fill" : "pause.fill") {
                            paused ? torrent.resume(id: item.id) : torrent.pause(id: item.id)
                        }
                        if finished {
                            // Close the panel first: it is keyboard-transparent and
                            // hands focus back to the app underneath after clicks, which
                            // would yank Finder straight back down (the "flash and hide").
                            // With the popover closed, maybeReturnFocus() early-returns and
                            // Finder stays forward — same pattern as clipboard copy-and-paste.
                            rowIcon("folder") {
                                model.closePanel?()
                                torrent.revealInFinder(id: item.id)
                            }
                        }
                        rowIcon("xmark") { confirmingRemove = item.id }
                    }
                }
            }
            // Line 2 (dim): percent + files done/total + speeds + eta.
            if confirmingRemove != item.id {
                secondLine(item: item, pct: pct, finished: finished, stats: stats)
            }
            // Expanded: per-file list with individual on/off + progress.
            if confirmingRemove != item.id, torrent.expandedIds.contains(item.id), item.files.count > 1 {
                fileList(item)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
    }

    /// Per-file rows under an expanded torrent: a switch to include/exclude each
    /// file (rqbit re-selects live, so toggling on resumes a skipped file), the
    /// name, and its own progress — done ✓, a percent while downloading, or "—"
    /// when excluded. No inner scroll — the whole panel is the single scroll.
    private func fileList(_ item: TorrentController.TorrentItem) -> some View {
        let progress = item.stats?.fileProgressBytes ?? []
        let selectedCount = item.files.filter { $0.selected }.count
        return VStack(spacing: 3) {
            Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 2)
            // Bulk toggle: select / deselect every file at once, with a live count.
            HStack(spacing: 12) {
                Text("\(selectedCount)/\(item.files.count)")
                    .font(Theme.mono(9)).foregroundStyle(Theme.textTertiary).monospacedDigit()
                Spacer(minLength: 0)
                Button { torrent.setAllFilesSelected(id: item.id, selected: true) } label: {
                    HoverLabel(text: t(.torrentAll), size: 9, color: Theme.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { torrent.setAllFilesSelected(id: item.id, selected: false) } label: {
                    HoverLabel(text: t(.torrentNone), size: 9, color: Theme.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 1)
            ForEach(item.files, id: \.index) { file in
                fileRow(item, file, progress: progress)
            }
        }
        .padding(.top, 2)
    }

    private func fileRow(_ item: TorrentController.TorrentItem,
                         _ file: TorrentFile, progress: [Int64]) -> some View {
        let bytes = file.index < progress.count ? progress[file.index] : 0
        let done = file.lengthBytes > 0 && bytes >= file.lengthBytes
        let pct = file.lengthBytes > 0 ? Int(Double(bytes) / Double(file.lengthBytes) * 100) : 0
        return HStack(spacing: 8) {
            Theme.MiniSwitch(isOn: Binding(
                get: { file.selected },
                set: { on in torrent.setFileSelected(id: item.id, fileIndex: file.index, on: on) }
            ))
            Text(shortName(file.name))
                .font(Theme.mono(10))
                .foregroundStyle(file.selected ? Theme.listText : Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Group {
                if !file.selected {
                    // Excluded file: show what was already downloaded of it (Anton) —
                    // partial data may still be on disk — not just its total size.
                    Text(bytes > 0
                         ? "\(SizeFormatting.sizeText(bytes)) / \(SizeFormatting.sizeText(file.lengthBytes))"
                         : SizeFormatting.sizeText(file.lengthBytes))
                        .foregroundStyle(Theme.textTertiary)
                } else if done {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accentGreen)
                } else {
                    Text("\(pct)%").foregroundStyle(Theme.textSecondary).monospacedDigit()
                }
            }
            .font(Theme.mono(10))
            .fixedSize()
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func secondLine(item: TorrentController.TorrentItem, pct: Int, finished: Bool, stats: TorrentStats?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if item.filesMissing {
                // Payload was deleted from disk under the download; the torrent is
                // paused. Tapping the play button (already visible) re-downloads.
                Text(t(.torrentFilesRemoved))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.accentRed)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if finished {
                Text("100%")
                    .font(Theme.mono(9.5, weight: .semibold))
                    .foregroundStyle(Theme.accentGreen)
                    .monospacedDigit()
                Text(doneTail(stats: stats))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                // Always ONE line: a compact stat font (like the speed panel), and
                // minimumScaleFactor shrinks it a touch for the long cases (many
                // files, big sizes, multi-day ETA) rather than ever wrapping to a
                // second or third row.
                Text(downloadingTail(item: item, pct: pct, stats: stats))
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }

    /// Line-2 while downloading: "12% · 4/22 · 0.8 / 5.0 GB · ↓ 1.6 MB/s · 1h 33m".
    /// File fraction only for multi-file torrents (a lone "1/1" is noise) + the
    /// downloaded/total size + download rate + eta. Upload is deliberately omitted
    /// here — it only matters once done (shown on the finished row), and dropping
    /// it keeps this line on one row. Done count from rqbit's per-file byte progress.
    private func downloadingTail(item: TorrentController.TorrentItem, pct: Int, stats: TorrentStats?) -> String {
        var parts: [String] = ["\(pct)%"]
        let selected = item.files.filter { $0.selected }
        if selected.count > 1 {
            let progress = stats?.fileProgressBytes ?? []
            let done = selected.filter { $0.index < progress.count && progress[$0.index] >= $0.lengthBytes }.count
            parts.append("\(done)/\(selected.count)")
        }
        if let s = stats, s.totalBytes > 0 {
            parts.append("\(SizeFormatting.sizeText(s.progressBytes)) / \(SizeFormatting.sizeText(s.totalBytes))")
        }
        parts.append("↓\(rate(stats?.downloadBps ?? 0))")
        parts.append(etaText(stats?.etaSeconds))
        return parts.joined(separator: " · ")
    }

    /// Line-2 when finished: "100% · 4.8 GB · ↑ 40 KB/s" — total size + seed rate.
    private func doneTail(stats: TorrentStats?) -> String {
        var parts: [String] = []
        if let s = stats, s.totalBytes > 0 { parts.append(SizeFormatting.sizeText(s.totalBytes)) }
        parts.append("↑\(rate(stats?.uploadBps ?? 0))")
        return "· " + parts.joined(separator: " · ")
    }

    private func removeConfirm(_ item: TorrentController.TorrentItem) -> some View {
        // The two destructive options sit at the row's left edge (same edge as the
        // name/icons); "cancel" is pushed to the far right, away from them, so a
        // reflexive tap doesn't land on a delete. "delete torrent" (red) drops the
        // torrent but leaves the download on disk; "delete with files" (red) erases it too.
        HStack(spacing: 16) {
            Button {
                confirmingRemove = nil
                torrent.remove(id: item.id, deleteFiles: false)
            } label: {
                HoverLabel(text: t(item.fromMagnet ? .torrentRemoveMagnet : .torrentRemoveTorrent),
                           size: 10, color: Theme.accentRed)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                confirmingRemove = nil
                torrent.remove(id: item.id, deleteFiles: true)
            } label: {
                HoverLabel(text: t(.torrentRemoveDelete), size: 10, color: Theme.accentRed)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button {
                confirmingRemove = nil
            } label: {
                HoverLabel(text: t(.quitCancel), size: 10, color: Theme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Actions

    /// Context-aware add: a magnet already on the clipboard wins over the file
    /// picker, so one button covers both paths without asking which is meant.
    private func addTapped() {
        if let s = NSPasteboard.general.string(forType: .string),
           s.lowercased().hasPrefix("magnet:") {
            add(source: .link(s))
        } else {
            openTorrentPicker()
        }
    }

    /// Pick a `.torrent` from disk (NSOpenPanel, restricted to the torrent type)
    /// and hand its bytes to the add sheet. The primary add path, since the
    /// popover can't reliably host a Finder drag.
    private func openTorrentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Start in Downloads (where browsers save .torrent files); the sidebar
        // still lets the user browse anywhere.
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let torrentType = UTType(filenameExtension: "torrent") {
            panel.allowedContentTypes = [torrentType]
        }
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        add(source: .file(data))
    }

    /// Open the add sheet immediately; it fetches the file list inside itself and
    /// shows a "fetching…" state meanwhile, so a magnet paste isn't silent for
    /// seconds. The sheet — not this view — runs fetchFiles and confirmAdd.
    private func add(source: TorrentController.AddSource) {
        model.openTorrentAddSheet?(source)
    }

    private func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Helpers

    private func rowIcon(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
    }

    /// Last path component, so a nested file shows its name, not the full path.
    private func shortName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" }).last.map(String.init) ?? name
        return last.isEmpty ? name : last
    }

    /// Decimal byte-rate (like the converter's sizes) with a localized unit —
    /// every speed carries its own unit, no bare numbers.
    private func rate(_ bps: Int64) -> String {
        let b = Double(max(0, bps))
        if b >= 1_000_000 { return String(format: "%.1f %@", b / 1_000_000, t(.unitMBs)) }
        if b >= 1000 { return String(format: "%.0f %@", b / 1000, t(.unitKBs)) }
        return "\(Int(b)) \(t(.unitBs))"
    }

    /// Compact remaining time (e.g. `6m 13s`); `—` when the engine has no estimate.
    private func etaText(_ seconds: Int?) -> String {
        guard let s = seconds, s > 0 else { return "—" }
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)\(t(.unitHour)) \(m)\(t(.unitMin))" }
        if m > 0 { return "\(m)\(t(.unitMin)) \(sec)\(t(.unitSec))" }
        return "\(sec)\(t(.unitSec))"
    }
}
