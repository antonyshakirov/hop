import SwiftUI

/// Screen-text module: one line — the name, then two actions. The crosshair
/// reads an area of the screen; the window is where a picture can be dropped or
/// pasted and where the recognized text is shown (Anton, 2026-07-25).
struct ScreenTextView: View {
    @ObservedObject var reader: ScreenTextController
    let lang: AppLanguage
    /// The panel has to close before the crosshair appears — a popover would
    /// cover the very thing the user is framing.
    var closePanel: () -> Void = {}
    var openWindow: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            ModuleMarkIcon(symbol: "text.viewfinder")
            Text(L10n.t(.ocrLabel, lang))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let status {
                Text(status.text)
                    .font(Theme.mono(9))
                    .foregroundStyle(status.color)
                    .lineLimit(1)
            }
            action("rectangle.dashed", help: L10n.t(.ocrRead, lang)) {
                closePanel()
                reader.capture()
            }
            action("arrow.up.forward.app", help: L10n.t(.ocrPaste, lang)) {
                openWindow()
            }
        }
    }

    private func action(_ symbol: String, help: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            RowActionIcon(symbol: symbol)
        }
        .buttonStyle(.plain)
        .hoverHighlight(5)
        .help(help)
        .disabled(reader.isBusy)
    }

    /// The short line on the right: what the last pass did.
    private var status: (text: String, color: Color)? {
        switch reader.state {
        case .idle: return nil
        case .selecting: return (L10n.t(.ocrSelecting, lang), Theme.textTertiary)
        case .reading: return (L10n.t(.ocrReading, lang), Theme.textTertiary)
        case .done(let count): return ("\(L10n.t(.ocrCopied, lang)) · \(count)", Theme.accentGreen)
        case .empty: return (L10n.t(.ocrNothing, lang), Theme.textTertiary)
        case .denied: return (L10n.t(.ocrNeedsPermission, lang), Theme.accentYellow)
        case .failed: return (L10n.t(.ocrFailed, lang), Theme.accentRed)
        }
    }
}
