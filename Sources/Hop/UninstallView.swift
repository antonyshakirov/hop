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

    /// TWO actions, named: "remove an app" and "clean up". A single row that opened
    /// a window with tabs inside meant you could not tell what you were about to do
    /// until it was open (Anton, 2026-07-30).
    var body: some View {
        HStack(spacing: 6) {
            action(.uninstall, symbol: "trash", label: .uninstallModeApp)
            action(.clean, symbol: "sparkles", label: .uninstallModeClean)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(targeted ? Theme.editing : .clear, lineWidth: 1)
        )
        .snapshotAwareDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task {
                for provider in providers {
                    if let url = await DroppedFiles.url(from: provider) {
                        uninstall.mode = .uninstall
                        uninstall.choose(path: url.path)
                        break   // one app at a time: the window shows what it found
                    }
                }
                openWindow()
            }
            return true
        }
    }

    private func action(_ mode: UninstallController.Mode, symbol: String,
                        label: L10nKey) -> some View {
        Button {
            uninstall.start(mode: mode)
            openWindow()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(targeted ? Theme.editing : Theme.textSecondary)
                Text(L10n.t(label, lang))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .hoverHighlight(7)
        .help(L10n.t(label, lang))
    }
}
