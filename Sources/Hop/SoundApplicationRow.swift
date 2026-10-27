import SwiftUI
import HopCore

struct SoundMixerChannelRow: View {
    @ObservedObject var channel: SoundMixerChannel
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    @State private var choosingOutput = false
    private var editable: Bool { mixer.running }
    private var destination: String {
        guard let uid = channel.preference.outputUID else { return L10n.t(.soundSystemDefault, lang) }
        return mixer.outputDevices.first { $0.uid == uid }?.name ?? channel.preference.outputName ?? uid
    }
    private var status: String {
        let key: L10nKey
        if !channel.appRunning { key = .soundAppNotRunning }
        else if !mixer.requested { key = .soundDisabled }
        else {
            switch channel.routeState {
            case .waiting: key = .soundAppWaiting
            case .failed: key = .soundAppRouteFailed
            case .preparing: key = .soundMixerStarting
            case .playing: key = channel.hasAudio ? .soundAppPlaying : .soundAppIdle
            case .stopped: key = .soundAppIdle
            }
        }
        return L10n.t(key, lang)
    }
    private var destinationIcon: String {
        switch channel.routeState {
        case .waiting: return "pause.circle"
        case .failed: return "exclamationmark.circle"
        default: return "chevron.down"
        }
    }
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = channel.icon { Image(nsImage: icon).resizable().interpolation(.high) }
                    else { Image(systemName: "app").resizable().foregroundStyle(Theme.textTertiary) }
                }.frame(width: 22, height: 22)
                    .saturation(editable ? 1 : 0)
                    .brightness(editable ? 0 : (Theme.isDark ? -0.35 : 0.35))
                Circle().fill(!editable ? Theme.disabledForeground : channel.hasAudio ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 5, height: 5)
            }.help(status).accessibilityLabel(status)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(channel.name).font(Theme.mono(11)).lineLimit(1).truncationMode(.middle)
                    if channel.preference.pinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                }.foregroundStyle(!editable ? Theme.disabledForeground : channel.appRunning ? Theme.textPrimary : Theme.textSecondary)
                    .help(channel.name + " · " + status)
                Button { choosingOutput.toggle() } label: {
                    HStack(spacing: 4) {
                        Text(destination).lineLimit(1).truncationMode(.middle)
                        Image(systemName: destinationIcon)
                            .font(.system(size: 8))
                    }.font(Theme.mono(9)).foregroundStyle(editable ? Theme.textTertiary : Theme.disabledForeground)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).hoverHighlight(4)
                    .help(destination + " · " + status)
                    .accessibilityLabel(channel.name + ": " + L10n.t(.soundOutput, lang))
                    .accessibilityValue(destination + " · " + status)
                    .popover(isPresented: $choosingOutput, arrowEdge: .bottom) { outputChoices }
            }.frame(width: 132, alignment: .leading)
            SoundVolumeControl(device: SoundDevice(uid: channel.id, name: channel.name, volume: channel.settings.gain,
                muted: channel.settings.muted, canChangeVolume: true, canMute: true),
                direction: .output, lang: lang, maximum: 1, label: .soundMixerGain, showLabel: false) { value in
                mixer.update(channel) { $0.gain = value }
            }.disabled(!editable).help(L10n.t(.soundAppVolumeHint, lang))
            Button { mixer.update(channel) { $0.muted.toggle() } } label: {
                Image(systemName: channel.settings.muted ? "speaker.slash.fill" : "speaker.wave.2")
                    .font(.system(size: 13)).foregroundStyle(!editable ? Theme.disabledForeground : channel.settings.muted ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 30, height: 28).background(editable ? Theme.chipBg : Theme.disabledSurface, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).hoverHighlight(6).disabled(!editable)
                .help(channel.name + ": " + L10n.t(channel.settings.muted ? .soundUnmute : .soundMute, lang))
                .accessibilityLabel(channel.name + ": " + L10n.t(channel.settings.muted ? .soundUnmute : .soundMute, lang))
                .accessibilityValue(channel.settings.muted ? "1" : "0")
            if Snapshot.active { orderIcon }
            else {
                Menu {
                    Button(L10n.t(channel.preference.pinned ? .soundAppUnpin : .soundAppPin, lang)) { mixer.togglePin(channel) }
                    Divider()
                    Button(L10n.t(.soundAppMoveUp, lang)) { mixer.move(channel, by: -1) }.disabled(!mixer.canMove(channel, by: -1))
                    Button(L10n.t(.soundAppMoveDown, lang)) { mixer.move(channel, by: 1) }.disabled(!mixer.canMove(channel, by: 1))
                } label: { orderIcon }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel(channel.name + ": " + L10n.t(.soundMixerApps, lang))
            }
        }.frame(height: 40).disabled(!editable).allowsHitTesting(!Snapshot.active)
            .onChange(of: mixer.running) { _, running in if !running { choosingOutput = false } }
    }
    private var orderIcon: some View {
        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(editable ? Theme.textSecondary : Theme.disabledForeground).frame(width: 20, height: 28)
    }
    var outputChoices: some View {
        SoundDeviceChoices { outputChoiceContent }
    }
    var outputChoiceContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            choice(L10n.t(.soundSystemDefault, lang), uid: nil)
            Divider().padding(.vertical, 4)
            ForEach(mixer.outputDevices) { device in choice(device.name, uid: device.uid) }
            if let uid = channel.preference.outputUID, !mixer.outputDevices.contains(where: { $0.uid == uid }) {
                Text(destination + " · " + L10n.t(.soundAppWaiting, lang))
                    .font(Theme.mono(10)).foregroundStyle(Theme.textTertiary).padding(8)
            }
        }.padding(8)
    }
    private func choice(_ name: String, uid: String?) -> some View {
        Button { mixer.selectOutput(channel, uid: uid); choosingOutput = false } label: {
            HStack(spacing: 8) {
                Image(systemName: channel.preference.outputUID == uid ? "checkmark" : "circle")
                    .foregroundStyle(channel.preference.outputUID == uid ? Theme.textPrimary : Theme.textTertiary)
                Text(name).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Spacer(minLength: 0)
            }.font(Theme.mono(11)).padding(8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).hoverHighlight(5)
    }
}
