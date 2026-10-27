import SwiftUI

/// One illustration for both routes, without audio controllers or permissions.
struct SoundOnboardingArt: View {
    let lang: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t(.soundOutput, lang))
                .font(Theme.mono(10, weight: .semibold))
            route("Spotify", symbol: "music.note", output: "speaker.wave.2", level: 0.45)
            route("Telegram", symbol: "paperplane", output: "headphones", level: 1)
            Rectangle().fill(Theme.divider).frame(height: 1)
            HStack(spacing: 10) {
                Image(systemName: "mic")
                Text("+")
                Image(systemName: "music.note")
                Image(systemName: "arrow.right")
                    .foregroundStyle(Theme.textTertiary)
                Text("Hop Mix").font(Theme.mono(11, weight: .semibold))
            }
            .font(.system(size: 13))
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelBackground)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func route(_ name: String, symbol: String, output: String, level: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 16)
            Text(name).font(Theme.mono(10)).frame(width: 76, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.divider)
                    Capsule().fill(Theme.textSecondary).frame(width: geometry.size.width * level)
                }
                .frame(height: 3).frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            Image(systemName: "arrow.right").foregroundStyle(Theme.textTertiary)
            Image(systemName: output).frame(width: 22)
        }
        .font(.system(size: 12))
    }
}
