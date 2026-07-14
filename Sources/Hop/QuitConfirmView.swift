import SwiftUI

/// Quit confirmation while a timer is running or keep-awake is active:
/// a branded centered window instead of silently killing the work.
struct QuitConfirmView: View {
    let onQuit: () -> Void
    let onCancel: () -> Void

    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(spacing: 12) {
            Text(t(.quitConfirmTitle))
                .font(Theme.mono(14, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(t(.quitConfirmBody))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.docText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text(t(.quitCancel))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                Button(action: onQuit) {
                    Text(t(.quitConfirm))
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 300)
        .background(Theme.panelBackground)
    }
}
