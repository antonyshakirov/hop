import SwiftUI
import HopCore

struct SoundCallMixView: View {
    @ObservedObject var call: SoundCallMixController
    @ObservedObject var sound: SoundController
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack(alignment: .leading) {
                    ForEach([L10nKey.soundMixerStarting, .soundEnabled, .soundDisabled], id: \.self) { key in
                        Text(L10n.t(.soundCallMix, lang) + " · " + L10n.t(key, lang)).hidden()
                    }
                    Text(L10n.t(.soundCallMix, lang) + " · " + L10n.t(call.starting ? .soundMixerStarting : call.running ? .soundEnabled : .soundDisabled, lang))
                }
                .font(Theme.mono(16)).foregroundStyle(Theme.textPrimary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t(.soundCallMix, lang) + " · " + L10n.t(call.starting ? .soundMixerStarting : call.running ? .soundEnabled : .soundDisabled, lang))
                Spacer()
                Button {
                    if call.running || call.starting { call.stop() }
                    else { sound.stopCheck(); sound.discardRecording(); call.start(inputUID: sound.inputUID, apps: mixer.apps) }
                } label: {
                    ZStack {
                        Text(L10n.t(.soundCallStart, lang)).hidden()
                        Text(L10n.t(.soundCallStop, lang)).hidden()
                        Text(L10n.t(call.running || call.starting ? .soundCallStop : .soundCallStart, lang))
                    }.font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                        .padding(8).background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).hoverDim()
            }
            Text(L10n.t(.soundCallHint, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                source(L10n.t(.soundMicrophone, lang), settings: call.microphone, edit: call.editMicrophone)
                ForEach(mixer.apps.filter { SoundCallMixPolicy.allows($0.id) }) { app in
                    source(app.name, settings: call.settings(app.id)) { edit in call.editApplication(app.id, edit) }
                }
            }.disabled(!call.running || call.starting || call.requestingMicrophone)
            if let failure = call.failure {
                Text(L10n.t(failure == .permission ? .soundPermission : failure == .inputChanged ? .soundInputChanged : .soundCallFailed, lang))
                    .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(L10n.t(.soundCallCloseHint, lang))
    }
    private func source(_ name: String, settings: SoundChannelSettings,
                        edit: @escaping ((inout SoundChannelSettings) -> Void) -> Void) -> some View {
        HStack(spacing: 10) {
            Toggle(name, isOn: Binding(get: { settings.active }, set: { value in edit { $0.active = value } }))
                .toggleStyle(SoundSourceToggleStyle()).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                .frame(width: 135, alignment: .leading)
            SoundVolumeControl(device: SoundDevice(uid: name, name: name + " · " + SoundCallMixController.deviceName, volume: settings.gain,
                                                   muted: settings.muted, canChangeVolume: true, canMute: true),
                               direction: .input, lang: lang, maximum: 1, label: .soundMixerGain, showLabel: false) { value in edit { $0.gain = value } }
                .disabled(!settings.active || call.starting)
            Button { edit { $0.muted.toggle() } } label: {
                Image(systemName: settings.muted ? "speaker.slash.fill" : "speaker.wave.2")
                    .foregroundStyle(settings.muted ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 30, height: 28).background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).disabled(!settings.active || call.starting)
                .accessibilityLabel(name + " · " + SoundCallMixController.deviceName + ": " + L10n.t(settings.muted ? .soundUnmute : .soundMute, lang))
        }
    }
}

/// Matches Hop's plain square/check selection controls; no system-blue tint.
private struct SoundSourceToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(configuration.isOn ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 18, height: 18)
                configuration.label
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).hoverDim()
            .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}
