import SwiftUI
import HopCore

struct SoundCallMixView: View {
    @ObservedObject var call: SoundCallMixController
    @ObservedObject var sound: SoundController
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text(L10n.t(.soundCallMix, lang)).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    if call.running || call.starting { call.stop() }
                    else { sound.stopCheck(); sound.discardRecording(); call.start(inputUID: sound.inputUID, apps: mixer.apps) }
                } label: {
                    ZStack {
                        Text(L10n.t(.soundCallStart, lang)).hidden()
                        Text(L10n.t(.soundCallStop, lang)).hidden()
                        Text(L10n.t(call.running || call.starting ? .soundCallStop : .soundCallStart, lang))
                    }.font(Theme.mono(11)).foregroundStyle(call.running ? Theme.accentYellow : Theme.textPrimary)
                        .padding(8).background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).hoverDim()
            }
            Text(L10n.t(.soundCallHint, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            source(L10n.t(.soundMicrophone, lang), settings: call.microphone, edit: call.editMicrophone)
            ForEach(mixer.apps.filter { SoundCallMixPolicy.allows($0.id) }) { app in
                source(app.name, settings: call.settings(app.id)) { edit in call.editApplication(app.id, edit) }
            }
            if call.starting { Text(L10n.t(.soundMixerStarting, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary) }
            if let failure = call.failure {
                Text(L10n.t(failure == .permission ? .soundPermission : .soundFailed, lang))
                    .font(Theme.mono(10)).foregroundStyle(Theme.accentOrange).fixedSize(horizontal: false, vertical: true)
            }
        }.onChange(of: sound.inputUID) { _, uid in call.inputChanged(uid) }
    }
    private func source(_ name: String, settings: SoundChannelSettings,
                        edit: @escaping ((inout SoundChannelSettings) -> Void) -> Void) -> some View {
        HStack(spacing: 10) {
            Toggle(name, isOn: Binding(get: { settings.active }, set: { value in edit { $0.active = value } }))
                .toggleStyle(.checkbox).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                .frame(width: 135, alignment: .leading).disabled(call.running || call.starting)
            SoundVolumeControl(device: SoundDevice(uid: name, name: name + " · " + SoundCallMixController.deviceName, volume: settings.gain,
                                                   muted: settings.muted, canChangeVolume: true, canMute: true),
                               direction: .input, lang: lang, maximum: 1, label: .soundMixerGain, showLabel: false) { value in edit { $0.gain = value } }
                .disabled(!settings.active || call.starting)
            Button { edit { $0.muted.toggle() } } label: {
                Image(systemName: settings.muted ? "speaker.slash.fill" : "speaker.wave.2")
                    .foregroundStyle(settings.muted ? Theme.accentYellow : Theme.textSecondary)
                    .frame(width: 30, height: 28).background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).disabled(!settings.active || call.starting)
                .accessibilityLabel(name + " · " + SoundCallMixController.deviceName + ": " + L10n.t(settings.muted ? .soundUnmute : .soundMute, lang))
        }
    }
}
