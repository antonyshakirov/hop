import SwiftUI
import HopCore

struct SoundMixerSwitch: View {
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        SettingChip(active: mixer.requested, enabled: mixer.available && !Snapshot.active,
                    action: { if mixer.requested { mixer.stop() } else { mixer.start() } }) {
            ZStack {
                Label(L10n.t(.soundMixerStart, lang), systemImage: "slider.horizontal.3").hidden()
                Label(L10n.t(.soundMixerStop, lang), systemImage: "stop.circle").hidden()
                Label(L10n.t(.soundMixerStarting, lang), systemImage: "stop.circle").hidden()
                Label(L10n.t(mixer.starting ? .soundMixerStarting : mixer.requested ? .soundMixerStop : .soundMixerStart, lang),
                      systemImage: mixer.requested ? "stop.circle" : "slider.horizontal.3")
            }
                .font(Theme.mono(10))
        }
            .help(L10n.t(.soundMixerHint, lang))
    }
}

struct SoundMixerChannels: View {
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !mixer.available {
                Text(L10n.t(.soundMixerRequirement, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Text(L10n.t(.soundMixerApps, lang)).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    SoundMixerSwitch(mixer: mixer, lang: lang)
                }
                if !mixer.apps.isEmpty {
                    ForEach(mixer.apps) { channel in
                        SoundMixerChannelRow(channel: channel, mixer: mixer, lang: lang)
                    }
                } else {
                    Text(L10n.t(.soundMixerEmpty, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure = mixer.failure {
                    Text(L10n.t(failure == .permission ? .soundMixerPermission : .soundFailed, lang))
                        .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Button(L10n.t(.soundMixerStart, lang)) { mixer.start() }.buttonStyle(.plain).hoverDim()
                }
            }
        }
    }
}
