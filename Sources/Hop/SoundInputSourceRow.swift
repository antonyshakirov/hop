import SwiftUI
import HopCore

struct SoundInputSourceRow: View {
    let name: String
    var detail: String? = nil
    let settings: SoundChannelSettings
    let enabled: Bool
    var available = true
    var included = false
    var pinned = false
    let lang: AppLanguage
    var edit: ((inout SoundChannelSettings) -> Void) -> Void
    var pin: (() -> Void)? = nil
    var hide: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            SoundMixerSourceControls(enabled: enabled && !included && (available || settings.active)) {
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(get: { settings.active }, set: { value in edit { $0.active = value } })) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(name).lineLimit(1).truncationMode(.middle)
                                if pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                            }
                            if let detail {
                                Text(detail).font(Theme.mono(9)).foregroundStyle(enabled && !included ? Theme.textTertiary : Theme.disabledForeground).lineLimit(1)
                            }
                        }.help([name, detail].compactMap { $0 }.joined(separator: " · "))
                    }.toggleStyle(SoundSourceToggleStyle(previewHover: Snapshot.active && CommandLine.arguments.contains("--sound-hover-source") && name == "ZoomAudioDevice")).font(Theme.mono(11))
                        .foregroundStyle(enabled && !included ? Theme.textPrimary : Theme.disabledForeground)
                        .frame(width: 175, alignment: .leading)
                    SoundVolumeControl(device: SoundDevice(uid: name, name: name + " · " + SoundCallMixController.deviceName,
                        volume: settings.gain, muted: settings.muted, canChangeVolume: true, canMute: true),
                        direction: .input, lang: lang, maximum: 1, label: .soundMixerGain, showLabel: false) { value in edit { $0.gain = value } }
                        .disabled(!settings.active || !available)
                    Button { edit { $0.muted.toggle() } } label: {
                        Image(systemName: settings.muted ? "speaker.slash.fill" : "speaker.wave.2")
                            .foregroundStyle(!enabled || !available || included || !settings.active ? Theme.disabledForeground : settings.muted ? Theme.textPrimary : Theme.textSecondary)
                            .frame(width: 30, height: 28).background(enabled && available && !included && settings.active ? Theme.chipBg : Theme.disabledSurface, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).hoverHighlight(6).disabled(!settings.active || !available)
                        .accessibilityLabel(name + " · " + SoundCallMixController.deviceName + ": " + L10n.t(settings.muted ? .soundUnmute : .soundMute, lang))
                }
            }
            if let pin, let hide {
                if Snapshot.active { menuIcon }
                else {
                    Menu {
                        Button { pin() } label: { Label(L10n.t(pinned ? .soundSourceUnpin : .soundSourcePin, lang), systemImage: pinned ? "pin.slash" : "pin") }
                        Divider()
                        Button { hide() } label: { Label(L10n.t(.soundSourceHide, lang), systemImage: "eye.slash") }.disabled(settings.active)
                    } label: {
                        menuIcon
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel(name + ": " + L10n.t(.soundMixerInputs, lang))
                }
            } else { Color.clear.frame(width: 20, height: 28) }
        }.frame(minHeight: 40)
    }
    private var menuIcon: some View {
        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).frame(width: 20, height: 28)
    }
}

private struct SoundSourceToggleStyle: ToggleStyle {
    var previewHover = false
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .frame(width: 18, height: 18)
                configuration.label
            }.contentShape(Rectangle()).textSelection(.disabled)
        }.buttonStyle(SoundTextActionStyle(normal: configuration.isOn ? Theme.textPrimary : Theme.textSecondary, previewHover: previewHover))
            .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}
