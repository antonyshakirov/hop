import SwiftUI
import HopCore

struct SoundMixerSwitch: View {
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        Button { if mixer.running || mixer.starting { mixer.stop() } else { mixer.start() } } label: {
            Label(L10n.t(mixer.starting ? .soundMixerStarting : mixer.running ? .soundMixerStop : .soundMixerStart, lang),
                  systemImage: mixer.running || mixer.starting ? "stop.circle" : "slider.horizontal.3")
                .font(Theme.mono(11)).foregroundStyle(mixer.running ? Theme.accentYellow : Theme.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).hoverDim().disabled(!mixer.available || Snapshot.active)
            .help(L10n.t(.soundMixerHint, lang))
    }
}

struct SoundMixerChannels: View {
    @ObservedObject var mixer: SoundMixerController
    let input: Bool
    let lang: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !mixer.available {
                if !input { Text(L10n.t(.soundMixerRequirement, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary) }
            } else {
                let channels = input ? mixer.inputs : mixer.apps
                if !channels.isEmpty {
                    HStack {
                        Text(L10n.t(input ? .soundMixerInputs : .soundMixerApps, lang))
                            .font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        if input {
                            Button { mixer.toggleInputDenoise() } label: {
                                Label(L10n.t(.soundMixerDenoise, lang), systemImage: "waveform.badge.minus")
                                    .font(Theme.mono(10))
                                    .foregroundStyle(mixer.denoiseAll ? Theme.accentYellow : Theme.textSecondary)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(.plain).hoverDim()
                                .accessibilityLabel(L10n.t(.soundInput, lang) + " " + L10n.t(.soundMixerDenoise, lang))
                                .accessibilityValue(mixer.denoiseAll ? "1" : "0")
                        }
                    }
                    ForEach(channels) { channel in
                        SoundMixerChannelRow(channel: channel, mixer: mixer, lang: lang)
                    }
                } else if !input {
                    Text(L10n.t(.soundMixerEmpty, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                }
                if input, mixer.running {
                    Text(L10n.t(.soundMixerVirtualHint, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if input, let failure = mixer.failure {
                    Text(L10n.t(failure == .permission ? .soundPermission : .soundFailed, lang))
                        .font(Theme.mono(10)).foregroundStyle(Theme.accentOrange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SoundMixerMeter: View {
    @ObservedObject var level: SoundMixerLevel
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(index) / 12 < SoundLevel.normalized(rms: level.peak) ? Theme.accentYellow : Theme.chipBg)
            }
        }.frame(width: 70, height: 8)
    }
}

private struct SoundMixerChannelRow: View {
    @ObservedObject var channel: SoundMixerChannel
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                if channel.input {
                    Button { mixer.update(channel) { $0.active.toggle() } } label: {
                        Image(systemName: channel.settings.active ? "checkmark.square.fill" : "square")
                            .foregroundStyle(channel.settings.active ? Theme.accentYellow : Theme.textTertiary)
                    }.buttonStyle(.plain).accessibilityLabel(channel.name)
                        .accessibilityValue(channel.settings.active ? "1" : "0")
                } else { Image(systemName: "app.dashed").foregroundStyle(Theme.textTertiary) }
                Text(channel.name).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if mixer.running { SoundMixerMeter(level: channel.level) }
            }
            HStack(spacing: 12) {
                SoundVolumeControl(device: SoundDevice(uid: channel.id, name: channel.name, volume: channel.settings.gain,
                                                      muted: channel.settings.muted, canChangeVolume: true, canMute: true),
                                   direction: channel.input ? .input : .output, lang: lang, maximum: 2, label: .soundMixerGain) { value in
                    mixer.update(channel) { $0.gain = value }
                }
                Button { mixer.update(channel) { $0.muted.toggle() } } label: {
                    Label(L10n.t(channel.settings.muted ? .soundUnmute : .soundMute, lang),
                          systemImage: channel.settings.muted ? "speaker.wave.2" : "speaker.slash")
                        .font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).hoverDim()
            }
            if channel.input {
                HStack(spacing: 8) {
                    effect(.soundMixerDenoise, icon: "waveform.badge.minus", selected: channel.settings.denoise || mixer.denoiseAll) {
                        mixer.update(channel) { $0.denoise.toggle() }
                    }.disabled(mixer.denoiseAll)
                    effect(.soundMixerBass, icon: "waveform", selected: channel.settings.bass) {
                        mixer.update(channel) { $0.bass.toggle() }
                    }
                }
            }
        }.opacity(channel.settings.active ? 1 : 0.55)
    }
    private func effect(_ key: L10nKey, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n.t(key, lang), systemImage: icon).font(Theme.mono(10))
                .foregroundStyle(selected ? Theme.accentYellow : Theme.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).hoverDim()
    }
}
