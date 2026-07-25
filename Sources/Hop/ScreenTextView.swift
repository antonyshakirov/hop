import SwiftUI

/// Screen-text module: one button that hands over the selection crosshair, plus
/// a short receipt of what the last pass did. The result itself lives in the
/// clipboard history, so there is no list to keep here.
struct ScreenTextView: View {
    @ObservedObject var reader: ScreenTextController
    let lang: AppLanguage
    /// The panel has to close before the crosshair appears — a popover would
    /// cover the very thing the user is framing.
    var closePanel: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
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
            }
            HStack(spacing: 8) {
                Button {
                    closePanel()
                    reader.capture()
                } label: {
                    Text(L10n.t(.ocrRead, lang))
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(reader.isBusy)
                Spacer(minLength: 0)
                if reader.state == .denied {
                    // The only actionable state: macOS has asked, and the switch
                    // itself lives in System Settings.
                    Button {
                        if let url = URL(string: ScreenTextController.privacySettingsURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HoverLabel(text: L10n.t(.ocrOpenSettings, lang), size: 9,
                                   color: Theme.textSecondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(L10n.t(.ocrHint, lang))
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// The short line on the right of the header: what the last pass did.
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
