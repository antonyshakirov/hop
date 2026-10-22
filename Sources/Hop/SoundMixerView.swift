import SwiftUI
import HopCore

struct SoundMixerSwitch: View {
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        Button { if mixer.requested { mixer.stop() } else { mixer.start() } } label: {
            ZStack {
                Label(L10n.t(.soundMixerStart, lang), systemImage: "slider.horizontal.3").hidden()
                Label(L10n.t(.soundMixerStop, lang), systemImage: "stop.circle").hidden()
                Label(L10n.t(.soundMixerStarting, lang), systemImage: "stop.circle").hidden()
                Label(L10n.t(mixer.starting ? .soundMixerStarting : mixer.requested ? .soundMixerStop : .soundMixerStart, lang),
                      systemImage: mixer.requested ? "stop.circle" : "slider.horizontal.3")
            }
                .font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).hoverDim().disabled(!mixer.available || Snapshot.active)
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
                    Text(L10n.t(.soundMixerApps, lang)).font(Theme.mono(14)).foregroundStyle(Theme.textPrimary)
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

struct SoundMixerChannelRow: View {
    @ObservedObject var channel: SoundMixerChannel
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.dashed").foregroundStyle(Theme.textTertiary).frame(width: 16)
            Text(channel.name).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).truncationMode(.middle).frame(width: 110, alignment: .leading)
            SoundVolumeControl(device: SoundDevice(uid: channel.id, name: channel.name, volume: channel.settings.gain,
                                                  muted: channel.settings.muted, canChangeVolume: true, canMute: true),
                               direction: .output, lang: lang, maximum: 1, label: .soundMixerGain, showLabel: false) { value in
                mixer.update(channel) { $0.gain = value }
            }
            Button { mixer.update(channel) { $0.muted.toggle() } } label: {
                Image(systemName: channel.settings.muted ? "speaker.slash.fill" : "speaker.wave.2")
                    .font(.system(size: 13))
                    .foregroundStyle(channel.settings.muted ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 30, height: 28)
                    .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).hoverDim()
                .help(channel.name + ": " + L10n.t(channel.settings.muted ? .soundUnmute : .soundMute, lang))
                .accessibilityLabel(channel.name + ": " + L10n.t(channel.settings.muted ? .soundUnmute : .soundMute, lang))
                .accessibilityValue(channel.settings.muted ? "1" : "0")
        }.disabled(!mixer.running).opacity(mixer.running ? 1 : 0.5)
    }
}
