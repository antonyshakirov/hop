import SwiftUI
import HopCore
import UniformTypeIdentifiers

/// The archive window — the same shape as the converter's: a real window with a
/// drop zone that stays put while you drag onto it. The panel's popover closes
/// the moment a drag starts, so the module's row only opens this (Anton,
/// 2026-07-25).
struct ArchiveWindowView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    @AppStorage(ArchiveController.packFormatKey) private var packFormatRaw = PackFormat.zip.rawValue
    @AppStorage(ArchiveController.destinationKey) private var destinationRaw =
        ArchiveController.Destination.desktop.rawValue
    @AppStorage(ArchiveController.destinationPathKey) private var customPath = ""
    @State private var targeted = false

    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private var packFormat: PackFormat { PackFormat(rawValue: packFormatRaw) ?? .zip }
    private var destination: ArchiveController.Destination {
        ArchiveController.Destination(rawValue: destinationRaw) ?? .desktop
    }

    var body: some View {
        // ImageRenderer cannot draw a ScrollView, so a dev snapshot gets the
        // content flat — the same trick the converter window uses.
        Group {
            if Snapshot.active {
                content
            } else {
                ScrollView(showsIndicators: false) { content }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.panelBackground)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
                dropZone
                if !model.archive.pending.isEmpty {
                    queue
                    destinationRow
                    // The format belongs to PACKING only: an archive being opened
                    // comes out as whatever it already is, so the row is not shown
                    // when the queue is going to be unpacked (Anton, 2026-07-25).
                    if model.archive.plannedKind == .pack {
                        HStack(spacing: 6) {
                            Text(t(.convFormatLabel))
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 8)
                            ForEach(PackFormat.allCases) { option in
                                SettingChip(option.label, active: option == packFormat) {
                                    packFormatRaw = option.rawValue
                                }
                            }
                        }
                    }
                    runRow
                }
                // Being the opener for archives is a SETTING, not a window
                // control: it outlives this window and belongs next to the other
                // module settings, the way the torrent module's does (Anton,
                // 2026-07-25).
                if !model.archive.jobs.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(model.archive.jobs) { job in
                            ArchiveJobRow(job: job, helper: model.archive.helper, lang: lang)
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            model.archive.clear()
                        } label: {
                            HoverLabel(text: t(.convClear), size: 10, color: Theme.textTertiary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(model.themeVersion)
        // The window is exactly as tall as this, so an empty module opens as a
        // drop plate and nothing else — no hole under it (Anton, 2026-07-25).
        // Measured directly rather than through a PreferenceKey: the preference
        // reports 0 through a ScrollView, the same trap the converter hit.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.archiveContentHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, height in
                        model.archiveContentHeight = height
                    }
            }
        )
    }

    /// What is waiting for the button. Each row says what will happen to that
    /// file, and can be taken back out of the queue.
    private var queue: some View {
        VStack(spacing: 6) {
            ForEach(model.archive.pending, id: \.path) { url in
                let unpack = model.archive.willUnpack(url)
                HStack(spacing: 8) {
                    Image(systemName: unpack ? "arrow.down.left.and.arrow.up.right" : "doc")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 16)
                    Text(url.lastPathComponent)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.listText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        model.archive.removePending(url)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 20, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// Where the result goes. The Desktop is the default — an unpacked folder has
    /// to land where the user is already looking (Anton, 2026-07-25).
    private var destinationRow: some View {
        HStack(spacing: 6) {
            Text(t(.convDestLabel))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            SettingChip(t(.archiveDestDesktop), active: destination == .desktop) {
                destinationRaw = ArchiveController.Destination.desktop.rawValue
            }
            SettingChip(t(.convDestSame), active: destination == .alongside) {
                destinationRaw = ArchiveController.Destination.alongside.rawValue
            }
            Button {
                chooseFolder()
            } label: {
                Text(destination == .custom && !customPath.isEmpty
                     ? URL(fileURLWithPath: customPath).lastPathComponent : "…")
                    .font(Theme.mono(10))
                    .foregroundStyle(destination == .custom ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(destination == .custom ? Theme.chipBg : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(destination == .custom ? Theme.controlStroke : Theme.divider, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(5)
        }
    }

    /// The button that actually starts the work — nothing runs on a drop alone
    /// (Anton, 2026-07-25).
    private var runRow: some View {
        HStack(spacing: 14) {
            Button {
                model.archive.clearPending()
            } label: {
                HoverLabel(text: t(.archiveQueueClear), size: 10, color: Theme.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button {
                model.archive.start()
            } label: {
                Text(t(model.archive.plannedKind == .extract ? .archiveRunExtract : .archiveRunPack))
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(Theme.playFg)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverDim()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customPath = url.path
        destinationRaw = ArchiveController.Destination.custom.rawValue
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "archivebox")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(targeted ? Theme.editing : Theme.textTertiary)
            Text(t(.archiveDrop))
                .font(Theme.mono(11))
                .foregroundStyle(targeted ? Theme.editing : Theme.textSecondary)
                .multilineTextAlignment(.center)
            Text(t(.archiveDropHint))
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            Text(t(.archivePasteHint))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Theme.editing : Theme.divider,
                              style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [5, 4]))
        )
        .contentShape(Rectangle())
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await DroppedFiles.url(from: provider) { urls.append(url) }
                }
                model.archive.handleDrop(urls)
            }
            return true
        }
    }
}

/// One archive job, shared by the window and (while running) nothing else.
struct ArchiveJobRow: View {
    let job: ArchiveController.Job
    @ObservedObject var helper: ToolInstaller
    let lang: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: job.kind == .extract
                  ? "arrow.down.left.and.arrow.up.right" : "shippingbox")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)
            Text(job.name)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.listText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(stateText)
                .font(Theme.mono(9.5))
                .foregroundStyle(stateColor)
                .lineLimit(1)
            if case .done(let path) = job.state {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(4)
                .help(L10n.t(.torrentReveal, lang))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
    }

    private var stateText: String {
        switch job.state {
        case .waitingForHelper:
            if case .downloading(let fraction) = helper.state {
                return "\(L10n.t(.archiveGettingHelper, lang)) \(Int(fraction * 100))%"
            }
            return L10n.t(.archiveGettingHelper, lang)
        case .running:
            return L10n.t(job.kind == .extract ? .archiveUnpacking : .archivePacking, lang)
        case .done:
            return L10n.t(job.kind == .extract ? .archiveUnpacked : .archivePacked, lang)
        case .failed(let failure):
            switch failure {
            case .helper: return L10n.t(.archiveHelperFailed, lang)
            case .empty: return L10n.t(.archiveEmpty, lang)
            case .denied: return L10n.t(.archiveDenied, lang)
            case .tool: return L10n.t(.archiveFailed, lang)
            }
        }
    }

    private var stateColor: Color {
        switch job.state {
        case .done: return Theme.accentGreen
        case .failed: return Theme.accentRed
        default: return Theme.textTertiary
        }
    }
}
