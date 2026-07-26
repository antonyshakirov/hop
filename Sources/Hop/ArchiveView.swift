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

    /// Every format the module opens, in the order a user meets them. Built from
    /// `ArchiveFormat` so a new case can never quietly go unlisted. It is shown
    /// in the WINDOW, under the drop plate: the panel row stays one line
    /// (Anton, 2026-07-26).
    static let formats: String = ArchiveFormat.allCases
        .map(\.displayName)
        .joined(separator: " · ")

    var body: some View {
        Button {
            openWindow()
        } label: {
            // One line, exactly like the converter's row: the formats belong in
            // the window and the help, not on the panel, where they cost a whole
            // second line for a list nobody reads twice (Anton, 2026-07-26).
            HStack(spacing: 6) {
                ModuleMarkIcon(symbol: "archivebox",
                               color: targeted ? Theme.editing : Theme.textSecondary)
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
                RowActionIcon(symbol: "arrow.up.forward.app", compact: true)
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

/// The "open archives with Hop" switch. It lives in settings rather than in the
/// archive window: being the opener outlives any window and works with the
/// module hidden (Anton, 2026-07-25). The state is read from Launch Services on
/// appear — the opener may have been changed in Finder since.
struct ArchiveDefaultHandlerRow: View {
    let label: String

    @State private var isOn = false

    var body: some View {
        // The same card the torrent module offers for .torrent / magnet — the
        // two "let Hop open these" offers must look like one another (Anton,
        // 2026-07-26). A switch rather than a one-shot button, because handing
        // the types back has to be as easy as claiming them.
        HStack {
            Text(label)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Theme.MiniSwitch(isOn: Binding(
                get: { isOn },
                set: { on in
                    isOn = on
                    ArchiveController.setDefaultHandler(on)
                }))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .onAppear { isOn = ArchiveController.isDefaultHandler }
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
