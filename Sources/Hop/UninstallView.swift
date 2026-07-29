import HopCore
import SwiftUI
import UniformTypeIdentifiers

/// The uninstaller's row in the panel: one line that opens its window, the same
/// shape the converter and the archives use. A drop straight onto the row works
/// too, but the window is the real target — a popover closes the moment a drag
/// begins, which would pull the target out from under the file.
struct UninstallView: View {
    @ObservedObject var uninstall: UninstallController
    let lang: AppLanguage
    var openWindow: () -> Void = {}

    @State private var targeted = false

    var body: some View {
        Button {
            openWindow()
        } label: {
            HStack(spacing: 6) {
                ModuleMarkIcon(symbol: "trash",
                               color: targeted ? Theme.editing : Theme.textSecondary)
                Text(L10n.t(.uninstallLabel, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
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
        .help(L10n.t(.uninstallLabel, lang))
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                for provider in providers {
                    if let url = await DroppedFiles.url(from: provider) {
                        uninstall.choose(path: url.path)
                        break   // one app at a time: the window shows what it found
                    }
                }
                openWindow()
            }
            return true
        }
    }
}
