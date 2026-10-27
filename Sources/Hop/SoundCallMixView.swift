import SwiftUI
import HopCore

struct SoundCallMixView: View {
    @ObservedObject var call: SoundCallMixController
    @ObservedObject var sound: SoundController
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    private var controlsActive: Bool { call.running && !call.starting && !call.requestingMicrophone }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SoundMixerHeader(running: call.running, starting: call.starting, active: call.running || call.starting,
                             lang: lang, action: {
                if call.running || call.starting { call.stop() }
                else { sound.stopCheck(); sound.discardRecording(); call.start(inputUID: sound.inputUID, apps: mixer.apps) }
            })
            Text(L10n.t(.soundCallHint, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                source(L10n.t(.soundMicrophone, lang), settings: call.microphone, edit: call.editMicrophone)
                ForEach(mixer.apps.filter { SoundCallMixPolicy.allows($0.id) }) { app in
                    source(app.name, settings: call.settings(app.id), available: !app.processes.isEmpty) { edit in call.editApplication(app.id, edit) }
                }
            }.disabled(!controlsActive)
            if let failure = call.failure {
                Text(L10n.t(failure == .permission ? .soundPermission : failure == .inputChanged ? .soundInputChanged : .soundCallFailed, lang))
                    .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(L10n.t(.soundCallCloseHint, lang))
    }
    private func source(_ name: String, settings: SoundChannelSettings, available: Bool = true,
                        edit: @escaping ((inout SoundChannelSettings) -> Void) -> Void) -> some View {
        let enabled = controlsActive && available
        return HStack(spacing: 10) {
            Toggle(name, isOn: Binding(get: { settings.active }, set: { value in edit { $0.active = value } }))
                .toggleStyle(SoundSourceToggleStyle()).font(Theme.mono(11)).foregroundStyle(enabled ? Theme.textPrimary : Theme.disabledForeground)
                .frame(width: 135, alignment: .leading)
            SoundVolumeControl(device: SoundDevice(uid: name, name: name + " · " + SoundCallMixController.deviceName, volume: settings.gain,
                                                   muted: settings.muted, canChangeVolume: true, canMute: true),
                               direction: .input, lang: lang, maximum: 1, label: .soundMixerGain, showLabel: false) { value in edit { $0.gain = value } }
                .disabled(!settings.active || call.starting)
            Button { edit { $0.muted.toggle() } } label: {
                Image(systemName: settings.muted ? "speaker.slash.fill" : "speaker.wave.2")
                    .foregroundStyle(!enabled || !settings.active ? Theme.disabledForeground : settings.muted ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 30, height: 28).background(enabled && settings.active ? Theme.chipBg : Theme.disabledSurface, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).disabled(!settings.active || call.starting)
                .accessibilityLabel(name + " · " + SoundCallMixController.deviceName + ": " + L10n.t(settings.muted ? .soundUnmute : .soundMute, lang))
        }.disabled(!enabled)
    }
}

/// Matches Hop's plain square/check selection controls; no system-blue tint.
private struct SoundSourceToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var controlsEnabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(!controlsEnabled ? Theme.disabledForeground : configuration.isOn ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 18, height: 18)
                configuration.label
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).hoverHighlight(5)
            .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}
