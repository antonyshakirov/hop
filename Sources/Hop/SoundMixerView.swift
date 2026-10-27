import AppKit
import HopCore
import SwiftUI

struct SoundMixerSourceControls<Content: View>: View {
    let enabled: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().disabled(!enabled)
            .transaction(value: enabled) { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

struct SoundMixerHeader: View {
    let running: Bool
    let starting: Bool
    let active: Bool
    var enabled = true
    let lang: AppLanguage
    let action: () -> Void
    private var state: L10nKey { starting ? .soundMixerStarting : running ? .soundEnabled : .soundDisabled }
    private var actionKey: L10nKey { active ? .soundMixerStop : .soundMixerStart }
    private func title(_ state: L10nKey) -> String { L10n.t(.soundCallMix, lang) + " · " + L10n.t(state, lang) }
    var body: some View {
        HStack {
            ZStack(alignment: .leading) {
                ForEach([L10nKey.soundMixerStarting, .soundEnabled, .soundDisabled], id: \.self) { key in
                    Text(title(key)).hidden()
                }
                Text(title(state))
            }
            .font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            .accessibilityElement(children: .ignore).accessibilityLabel(title(state))
            Spacer(minLength: 8)
            SettingChip(active: active, enabled: enabled, action: action) {
                ZStack {
                    Label(L10n.t(.soundMixerStart, lang), systemImage: "power").hidden()
                    Label(L10n.t(.soundMixerStop, lang), systemImage: "power").hidden()
                    Label(L10n.t(actionKey, lang), systemImage: "power")
                }.font(Theme.mono(10))
            }.fixedSize().help(L10n.t(actionKey, lang))
        }
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
                SoundMixerHeader(running: mixer.running, starting: mixer.starting, active: mixer.running || mixer.starting,
                                 lang: lang,
                                 action: { if mixer.running || mixer.starting { mixer.stop() } else { mixer.start() } })
                    .allowsHitTesting(!Snapshot.active)
                HStack(spacing: 8) {
                    SettingChip(active: false, action: chooseApplication) {
                        Label(L10n.t(.soundAddApplication, lang), systemImage: "plus").font(Theme.mono(10))
                    }
                    SettingChip(active: false, enabled: mixer.hasCustomApplicationAudio,
                                action: mixer.resetApplicationAudio) {
                        Label(L10n.t(.soundResetApplications, lang), systemImage: "arrow.counterclockwise").font(Theme.mono(10))
                    }
                }.disabled(!mixer.running).allowsHitTesting(!Snapshot.active)
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
                    Button(L10n.t(.soundMixerStart, lang)) { mixer.start() }.buttonStyle(.plain).hoverHighlight(4)
                }
            }
        }
    }
    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        mixer.addApplication(id: id, name: name)
    }
}
