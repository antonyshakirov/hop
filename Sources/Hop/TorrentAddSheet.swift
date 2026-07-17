import AppKit
import SwiftUI
import HopCore

/// File-selection sheet shown after a torrent's metadata is fetched: pick which
/// files to download, where to put them, and confirm against free disk space.
/// Presented as a standalone window (like the converter) — the status-bar
/// popover collapses on any outside click and can't host a multi-step choice.
/// Theme tokens only; SettingChip/MiniSwitch only; no repeatForever animation.
struct TorrentAddSheet: View {
    /// The source to add. The sheet opens instantly and fetches its file list in
    /// `.task`, so a magnet paste isn't silent while metadata resolves.
    let source: TorrentController.AddSource
    /// Plain `let`, not `@ObservedObject`: the sheet only calls methods and never
    /// reads a published property, so observing would just re-render (and re-stat
    /// the disk) every poll tick while other torrents update.
    let torrent: TorrentController
    /// Close the window. Cancel and Download both call it; nothing is added
    /// unless Download ran confirmAdd first.
    let onClose: () -> Void

    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    /// nil while the file list is still being fetched; set once it resolves.
    @State private var pending: TorrentController.PendingAdd?
    /// Set when the fetch throws (no engine, unreadable torrent): shows a short
    /// error line with Cancel instead of an endless "fetching…".
    @State private var failed = false
    @State private var selected: Set<Int> = []
    @State private var destPath: String
    /// The configured torrent folder (or ~/Downloads) — the "Downloads" chip target.
    private let defaultDirPath: String

    init(source: TorrentController.AddSource, torrent: TorrentController, onClose: @escaping () -> Void) {
        self.source = source
        self.torrent = torrent
        self.onClose = onClose
        let configured = UserDefaults.standard.string(forKey: TorrentController.downloadDirKey) ?? ""
        let def = configured.isEmpty
            ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
            : configured
        self.defaultDirPath = def
        _destPath = State(initialValue: def)
        // Snapshot dev render (--torrent-addsheet): seed `pending`/`selected` at
        // init instead of through `.task`, so the sheet is already fully populated
        // on its very first layout pass — ImageRenderer captures a single
        // synchronous render and can't wait out an async task's state update.
        if Snapshot.active {
            let demo = Snapshot.demoAddSheetPending()
            _pending = State(initialValue: demo.pending)
            _selected = State(initialValue: demo.selected)
        }
    }

    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    // MARK: - Derived numbers

    /// The fetched files with `selected` reflecting the live checklist, so
    /// DiskSpace.required only counts the checked files.
    private var selectedFiles: [TorrentFile] {
        (pending?.files ?? []).map {
            TorrentFile(index: $0.index, name: $0.name, lengthBytes: $0.lengthBytes,
                        selected: selected.contains($0.index))
        }
    }
    private var requiredBytes: Int64 { DiskSpace.required(for: selectedFiles) }
    private var availableBytes: Int64 {
        let values = try? URL(fileURLWithPath: destPath)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
    private var fits: Bool { DiskSpace.fits(requiredBytes: requiredBytes, availableBytes: availableBytes) }
    private var canDownload: Bool {
        guard let pending, !pending.files.isEmpty else { return false }
        return !selected.isEmpty && fits
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let pending {
                summaryRow(pending)
                fileList(pending)
                Rectangle().fill(Theme.divider).frame(height: 1)
                destinationRow
                freeSpaceLine
            } else if failed {
                errorState
            } else {
                fetchingState
            }
            buttons
        }
        .padding(20)
        .frame(width: 440)
        // No maxHeight:.infinity — the window sizes to this view's own fitting
        // height (see App.swift), so it fits the fetching/error state snugly and
        // grows as the file list appears instead of leaving a hole below. The
        // list is capped + scrolls internally, so the height stays bounded.
        .background(Theme.panelBackground)
        .task(id: source) {
            // Snapshot dev render (--torrent-addsheet): `pending`/`selected` are
            // already seeded in init — skip the network fetch entirely.
            if Snapshot.active { return }
            // Fetch the file list inside the sheet so the window appears instantly
            // and the "fetching…" state shows while a magnet's metadata resolves.
            // A do/catch, not try?: on a throw (no engine, unreadable torrent) we
            // flip to an error line instead of hanging on "fetching…" forever.
            do {
                let resolved = try await torrent.fetchFiles(source: source)
                pending = resolved
                selected = Set(resolved.files.map { $0.index })
            } catch {
                failed = true
            }
        }
    }

    private var errorState: some View {
        Text(t(.torrentReadFailed))
            .font(Theme.mono(11))
            .foregroundStyle(Theme.accentRed)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private var header: some View {
        Text(headerTitle)
            .font(Theme.mono(13, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(2)
            .truncationMode(.middle)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var headerTitle: String {
        if let name = pending?.name, !name.isEmpty { return name }
        return t(.torrentLabel)
    }

    private var fetchingState: some View {
        // Pre-metadata (magnet): a plain centered label — no spinner, so no
        // repeatForever. Populates once fetchFiles resolves with the file list.
        Text(t(.torrentFetching))
            .font(Theme.mono(11))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private func summaryRow(_ pending: TorrentController.PendingAdd) -> some View {
        HStack(spacing: 8) {
            Text(filesSummary(pending))
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            SettingChip(t(.torrentAll), active: selected.count == pending.files.count) {
                selected = Set(pending.files.map { $0.index })
            }
            SettingChip(t(.torrentNone), active: selected.isEmpty) {
                selected = []
            }
        }
    }

    private func filesSummary(_ pending: TorrentController.PendingAdd) -> String {
        t(.torrentFilesSummary)
            .replacingOccurrences(of: "%1$@", with: "\(selected.count)")
            .replacingOccurrences(of: "%2$@", with: "\(pending.files.count)")
            + " · " + SizeFormatting.sizeText(requiredBytes)
    }

    private func fileList(_ pending: TorrentController.PendingAdd) -> some View {
        // Capped inner scroll: a long payload scrolls instead of stretching the
        // window past the screen; the destination/buttons below stay pinned.
        // ImageRenderer can't draw ScrollView — snapshots render a flat stack.
        Group {
            if Snapshot.active {
                fileRows(pending)
            } else {
                ScrollView(showsIndicators: false) {
                    fileRows(pending)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func fileRows(_ pending: TorrentController.PendingAdd) -> some View {
        VStack(spacing: 4) {
            ForEach(pending.files, id: \.index) { file in
                HStack(spacing: 8) {
                    Theme.MiniSwitch(isOn: binding(file.index))
                    Text(shortName(file.name))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.listText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(SizeFormatting.sizeText(file.lengthBytes))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                        .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var destinationRow: some View {
        HStack(spacing: 8) {
            Text(t(.convDestLabel))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            SettingChip(t(.convDestDownloads), active: destPath == defaultDirPath) {
                destPath = defaultDirPath
            }
            // A SettingChip too, so the custom-folder control matches the
            // "Downloads" chip's height instead of sitting a few points shorter.
            SettingChip(destPath == defaultDirPath
                ? "…"
                : URL(fileURLWithPath: destPath).lastPathComponent,
                active: destPath != defaultDirPath) {
                chooseFolder()
            }
        }
    }

    private var freeSpaceLine: some View {
        // Red + Download disabled when the selection won't fit — the check is
        // HopCore's DiskSpace, unit-tested, so the math is shared with the model.
        HStack {
            Text(freeSpaceText)
                .font(Theme.mono(10))
                .foregroundStyle(fits ? Theme.textTertiary : Theme.accentRed)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var freeSpaceText: String {
        t(.torrentNeedsFree)
            .replacingOccurrences(of: "%1$@", with: SizeFormatting.sizeText(requiredBytes))
            .replacingOccurrences(of: "%2$@", with: SizeFormatting.sizeText(availableBytes))
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Text(t(.quitCancel))
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
            // Offer Download only once there is a file list to act on. While
            // fetching or after a read failure there is nothing to download, so
            // Cancel goes full-width instead of pairing with a ghosted button
            // whose dark text vanished against the dark window.
            if pending != nil {
                Button(action: download) {
                    Text(t(.torrentDownload))
                        .font(Theme.mono(11, weight: .bold))
                        // Disabled (nothing selected / won't fit): a readable muted
                        // chip, not 0.4-opacity of the green CTA — that faded the
                        // dark label into the background. Stays legibly inactive.
                        .foregroundStyle(canDownload ? Theme.playFg : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(canDownload ? Theme.playBg : Theme.chipBg,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(!canDownload)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Actions

    private func download() {
        guard canDownload, let pending else { return }
        let indices = selected
        let folder = URL(fileURLWithPath: destPath)
        // Await the add and close ONLY on success: the old fire-and-forget + immediate
        // onClose() meant a failed confirmAdd silently dropped the torrent (nothing
        // appeared, no error). On failure keep the sheet open and show the error line.
        Task {
            do {
                try await torrent.confirmAdd(pending, selectedIndices: indices, outputFolder: folder)
                onClose()
            } catch {
                failed = true
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            destPath = url.path
        }
    }

    private func binding(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { selected.contains(index) },
            set: { on in
                if on { selected.insert(index) } else { selected.remove(index) }
            }
        )
    }

    /// Last path component, so a nested file shows its name, not the full path.
    private func shortName(_ name: String) -> String {
        let last = name.split(whereSeparator: { $0 == "/" }).last.map(String.init) ?? name
        return last.isEmpty ? name : last
    }
}
