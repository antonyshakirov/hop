import SwiftUI
import HopCore

struct SoundCallMixView: View {
    @ObservedObject var call: SoundCallMixController
    @ObservedObject var sound: SoundController
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    private var controlsActive: Bool { call.running && !call.starting && !call.requestingMicrophone }
    private var physicalInputs: [SoundDevice] {
        sound.inputs.filter { SoundInputMixPreferences.allowsMicrophone($0.uid) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SoundMixerHeader(running: call.running, starting: call.starting, active: call.running || call.starting,
                             lang: lang, action: {
                if call.running || call.starting { call.stop() }
                else { sound.stopCheck(); sound.discardRecording(); call.start(inputUID: sound.inputUID, apps: mixer.apps) }
            })
            Text(L10n.t(.soundCallHint, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if call.accessoryMuted {
                Label(L10n.t(.soundMicrophone, lang) + " · " + L10n.t(.soundMuted, lang), systemImage: "mic.slash.fill")
                    .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            }
            SoundMixerSourceControls(enabled: controlsActive) {
                VStack(spacing: 12) {
                    source(L10n.t(.soundSystemDefault, lang),
                           detail: physicalInputs.first(where: { $0.uid == sound.inputUID })?.name ?? L10n.t(.soundNoDevice, lang),
                           settings: call.microphone, available: physicalInputs.contains { $0.uid == sound.inputUID },
                           edit: call.editMicrophone)
                    ForEach(physicalInputs) { device in
                        let included = call.microphone.active && device.uid == sound.inputUID
                        source(device.name, detail: included ? L10n.t(.soundInputIncluded, lang) : nil,
                               settings: call.microphoneSettings(uid: device.uid), available: !included) { edit in
                            call.editMicrophone(uid: device.uid, edit)
                        }
                    }
                    ForEach(mixer.apps.filter { SoundCallMixPolicy.allows($0.id) }) { app in
                        source(app.name, settings: call.settings(app.id), available: !app.processes.isEmpty) { edit in call.editApplication(app.id, edit) }
                    }
                }
            }
            if let failure = call.failure {
                Text(L10n.t(failure == .permission ? .soundPermission : failure == .inputChanged ? .soundInputChanged : .soundCallFailed, lang))
                    .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(L10n.t(.soundCallCloseHint, lang))
    }
    private func source(_ name: String, detail: String? = nil, settings: SoundChannelSettings, available: Bool = true,
                        edit: @escaping ((inout SoundChannelSettings) -> Void) -> Void) -> some View {
        let enabled = controlsActive && available
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { settings.active }, set: { value in edit { $0.active = value } })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).lineLimit(1)
                    if let detail { Text(detail).font(Theme.mono(9)).foregroundStyle(enabled ? Theme.textTertiary : Theme.disabledForeground).lineLimit(1) }
                }.help([name, detail].compactMap { $0 }.joined(separator: " · "))
            }
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
