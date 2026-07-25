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
    @State private var targeted = false

    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
    private var packFormat: PackFormat { PackFormat(rawValue: packFormatRaw) ?? .zip }

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
                // The format belongs to PACKING only: an archive being opened is
                // whatever it already is, so this never affects unpacking.
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
