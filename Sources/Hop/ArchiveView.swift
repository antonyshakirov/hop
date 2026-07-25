import SwiftUI
import HopCore
import UniformTypeIdentifiers

/// Archive module: one drop zone that unpacks archives and packs everything
/// else, plus a short list of what it just did.
struct ArchiveView: View {
    @ObservedObject var archive: ArchiveController
    @ObservedObject var helper: ToolInstaller
    let lang: AppLanguage

    @AppStorage(ArchiveController.packFormatKey) private var packFormatRaw = PackFormat.zip.rawValue
    @State private var targeted = false

    private var packFormat: PackFormat { PackFormat(rawValue: packFormatRaw) ?? .zip }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(L10n.t(.archiveLabel, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                ForEach(PackFormat.allCases) { option in
                    formatChip(option)
                }
            }
            dropZone
            ForEach(archive.jobs) { job in
                jobRow(job)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 2) {
            Text(L10n.t(.archiveDrop, lang))
                .font(Theme.mono(10))
                .foregroundStyle(targeted ? Theme.editing : Theme.textSecondary)
                .lineLimit(1)
            Text(L10n.t(.archiveDropHint, lang))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(targeted ? Theme.editing : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await DroppedFiles.url(from: provider) { urls.append(url) }
                }
                archive.handleDrop(urls)
            }
            return true
        }
    }

    /// The format a PACK job produces. Extraction ignores it — an archive is
    /// unpacked as whatever it already is.
    private func formatChip(_ option: PackFormat) -> some View {
        let active = option == packFormat
        return Button {
            packFormatRaw = option.rawValue
        } label: {
            Text(option.label)
                .font(Theme.mono(9))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(active ? Theme.chipBg : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
    }

    private func jobRow(_ job: ArchiveController.Job) -> some View {
        HStack(spacing: 6) {
            Image(systemName: job.kind == .extract ? "arrow.down.left.and.arrow.up.right" : "shippingbox")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14)
            Text(job.name)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.listText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            Text(stateText(job))
                .font(Theme.mono(9))
                .foregroundStyle(stateColor(job))
                .lineLimit(1)
            if case .done(let path) = job.state {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(4)
                .help(L10n.t(.torrentReveal, lang))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 5))
    }

    private func stateText(_ job: ArchiveController.Job) -> String {
        switch job.state {
        case .waitingForHelper:
            // the helper's own progress is more useful than a generic "wait"
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

    private func stateColor(_ job: ArchiveController.Job) -> Color {
        switch job.state {
        case .done: return Theme.accentGreen
        case .failed: return Theme.accentRed
        default: return Theme.textTertiary
        }
    }
}

/// Reading a file URL out of a drop provider. The panel, the converter window
/// and the torrent card each grew their own copy of this; new drop zones use
/// this one.
enum DroppedFiles {
    static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
