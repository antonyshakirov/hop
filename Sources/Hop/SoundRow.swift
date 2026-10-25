import AppKit
import HopCore
import SwiftUI

struct SoundRow: View {
    let lang: AppLanguage
    @ObservedObject var status: SoundMuteStatus
    var open: () -> Void
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    ModuleMarkIcon(symbol: "speaker.wave.2", color: Theme.textSecondary)
                    Text(L10n.t(.soundLabel, lang))
                        .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain).hoverHighlight(5)
            Spacer(minLength: 8)
            SoundRowMixerControls(mixer: model.soundMixer, call: model.soundCallMix, lang: lang, startInput: {
                model.soundPageRequest = .input
                model.openSoundWindow?()
                model.sound.stopCheck(); model.sound.discardRecording()
                model.soundCallMix.start(inputUID: model.sound.inputUID, apps: model.soundMixer.apps)
            })
            Button(action: open) {
                RowActionIcon(symbol: "slider.horizontal.3", compact: true)
            }.buttonStyle(.plain).hoverHighlight(5).help(L10n.t(.soundOpen, lang))
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct SoundRowMixerControls: View {
    @ObservedObject var mixer: SoundMixerController
    @ObservedObject var call: SoundCallMixController
    let lang: AppLanguage
    var startInput: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            SettingChip(active: mixer.running, enabled: mixer.available && !Snapshot.active,
                        action: { if mixer.requested { mixer.stop() } else { mixer.start() } }) {
                SoundQuickMixerLabel(direction: .soundOutput, starting: mixer.starting, running: mixer.running, lang: lang)
            }
            .help(L10n.t(mixer.failure == .permission ? .soundMixerPermission : mixer.requested ? .soundMixerStop : .soundMixerStart, lang))
            .accessibilityLabel(L10n.t(.soundOutput, lang))
            .accessibilityValue(L10n.t(mixer.starting ? .soundMixerStarting : mixer.running ? .soundEnabled : .soundDisabled, lang))
            .accessibilityIdentifier("sound.quick.output")
            if call.enabled {
                SettingChip(active: call.running, enabled: !Snapshot.active,
                            action: { if call.running || call.starting { call.stop() } else { startInput() } }) {
                    SoundQuickMixerLabel(direction: .soundInput, starting: call.starting, running: call.running, lang: lang)
                }
                .help(L10n.t(.soundCallHint, lang))
                .accessibilityLabel(L10n.t(.soundInput, lang) + " · " + SoundCallMixController.deviceName)
                .accessibilityValue(L10n.t(call.starting ? .soundMixerStarting : call.running ? .soundEnabled : .soundDisabled, lang))
                .accessibilityIdentifier("sound.quick.input")
            }
        }
    }
}

struct SoundQuickMixerLabel: View {
    let direction: L10nKey
    let starting: Bool
    let running: Bool
    let lang: AppLanguage

    var body: some View {
        VStack(spacing: 2) {
            Label(L10n.t(direction, lang), systemImage: starting ? "ellipsis.circle" : running ? "power.circle.fill" : "power.circle")
                .font(Theme.mono(10))
            ZStack {
                ForEach([L10nKey.soundMixerStarting, .soundEnabled, .soundDisabled], id: \.self) { key in
                    Text(L10n.t(key, lang)).hidden()
                }
                Text(L10n.t(starting ? .soundMixerStarting : running ? .soundEnabled : .soundDisabled, lang))
            }.font(Theme.mono(9)).foregroundStyle(Theme.textSecondary)
        }.lineLimit(1).fixedSize()
    }
}
