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
            SoundRowMixerControl(mixer: model.soundMixer, lang: lang)
            Button(action: open) {
                RowActionIcon(symbol: "slider.horizontal.3", compact: true)
            }.buttonStyle(.plain).hoverHighlight(5).help(L10n.t(.soundOpen, lang))
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct SoundRowMixerControl: View {
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    private var helpKey: L10nKey {
        if let failure = mixer.failure { return failure == .permission ? .soundMixerPermission : .soundFailed }
        return mixer.requested ? .soundMixerStop : .soundMixerStart
    }
    var body: some View {
        SettingChip(active: mixer.requested, enabled: mixer.available && !Snapshot.active,
                    action: { if mixer.requested { mixer.stop() } else { mixer.start() } }) {
            Text(L10n.t(.soundMixerApps, lang)).font(Theme.mono(10)).lineLimit(1)
        }
        .help(L10n.t(helpKey, lang))
        .accessibilityLabel(L10n.t(.soundMixerApps, lang) + ": " + L10n.t(helpKey, lang))
        .accessibilityValue(mixer.running ? "1" : "0")
    }
}
