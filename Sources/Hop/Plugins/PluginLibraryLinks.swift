import SwiftUI

struct PluginLibraryLinks: View {
    let lang: AppLanguage
    @Environment(\.openURL) private var openURL

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { links }
            VStack(alignment: .leading, spacing: 8) { links }
        }
        .font(Theme.mono(11))
        .tint(Theme.accentBlue)
    }

    @ViewBuilder private var links: some View {
        PluginActionButton(title: PluginCopy.text(.repository, lang), action: { openURL(PluginLibraryResources.repository) },
                           bordered: false, accessibilityID: "hop.plugins.repository")
            .fixedSize()
            .help(PluginLibraryResources.repository.absoluteString)
        PluginActionButton(title: PluginCopy.text(.contribute, lang), action: { openURL(PluginLibraryResources.contribute) },
                           bordered: false, accessibilityID: "hop.plugins.contribute")
            .fixedSize()
            .help(PluginLibraryResources.contribute.absoluteString)
    }
}
