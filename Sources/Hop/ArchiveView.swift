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
    /// `ArchiveFormat` so a new case can never quietly go unlisted.
    static let formats: String = ArchiveFormat.allCases
        .map(\.displayName)
        .joined(separator: " · ")

    var body: some View {
        Button {
            openWindow()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
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
                // The formats say what KIND of archive this is: zip files, not
                // "put it away in my archive" (Anton, 2026-07-25). ALL of them are
                // listed — an ellipsis leaves the reader guessing which ones it
                // hides (Anton, 2026-07-25) — which takes the FULL row width: on
                // the name's line the longest translations pushed the tail off.
                // Format names are identical in every language and stay
                // untranslated, like the converter's capability table.
                Text(ArchiveView.formats)
                    .font(Theme.mono(8))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
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
        HStack {
            Text(label)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Theme.MiniSwitch(isOn: Binding(
                get: { isOn },
                set: { on in
                    isOn = on
                    ArchiveController.setDefaultHandler(on)
                }))
        }
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
