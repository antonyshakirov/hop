import SwiftUI

struct AppQuitRow: View {
    let lang: AppLanguage
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                ModuleMarkIcon(symbol: "xmark.app", color: Theme.textSecondary)
                Text(L10n.t(.quitAppsTitle, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                RowActionIcon(symbol: "arrow.up.forward.app", compact: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .help(L10n.t(.purposeQuitApps, lang))
    }
}

struct AppQuitWindowView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    private var strings: AppQuitStrings {
        AppQuitStrings(title: t(.quitAppsTitle), quitAll: t(.quitAppsAll), quit: t(.menuQuit),
                       pin: t(.quitAppsPin), unpin: t(.quitAppsUnpin), cannotPin: t(.quitAppsCannotPin),
                       documentNotice: t(.quitAppsNotice), empty: t(.quitAppsEmpty),
                       requested: t(.quitAppsRequested), refused: t(.quitAppsRefused))
    }

    var body: some View {
        ScrollView {
            AppQuitView(controller: model.appQuit, strings: strings)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panelBackground)
        .id(model.themeVersion)
    }
}
