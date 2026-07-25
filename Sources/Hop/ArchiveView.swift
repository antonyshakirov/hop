import SwiftUI
import HopCore
import UniformTypeIdentifiers

/// The archive module's row in the panel: one line that opens the archive
/// window, exactly like the converter's. Dropping straight onto the row still
/// works, but the real drop target is the window — a popover closes as soon as
/// a drag starts, which would pull the target out from under the file.
struct ArchiveView: View {
    @ObservedObject var archive: ArchiveController
    let lang: AppLanguage
    var openWindow: () -> Void = {}

    @State private var targeted = false

    var body: some View {
        Button {
            openWindow()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(targeted ? Theme.editing : Theme.textSecondary)
                Text(L10n.t(.archiveLabel, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                // a job that is still running keeps its state visible without
                // opening the window
                if let running = archive.jobs.first(where: { $0.state == .running }) {
                    Text(L10n.t(running.kind == .extract ? .archiveUnpacking : .archivePacking, lang))
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
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
                .stroke(targeted ? Theme.editing : .clear, lineWidth: 1)
        )
        .hoverHighlight(7)
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = await DroppedFiles.url(from: provider) { urls.append(url) }
                }
                archive.handleDrop(urls)
                openWindow()
            }
            return true
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
