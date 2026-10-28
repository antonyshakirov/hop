import SwiftUI
import HopCore

struct SoundCallMixView: View {
    @ObservedObject var call: SoundCallMixController
    @ObservedObject var sound: SoundController
    @ObservedObject var mixer: SoundMixerController
    let lang: AppLanguage
    @State private var otherExpanded = false
    @State private var restoring = false
    @State private var otherHovering = false
    init(call: SoundCallMixController, sound: SoundController, mixer: SoundMixerController, lang: AppLanguage,
         initiallyExpanded: Bool = false) {
        self.call = call; self.sound = sound; self.mixer = mixer; self.lang = lang
        _otherExpanded = State(initialValue: initiallyExpanded)
    }
    private var controlsActive: Bool { call.running && !call.starting && !call.requestingMicrophone }
    private var physicalInputs: [SoundDevice] { sound.inputs.filter { SoundInputMixPreferences.allowsMicrophone($0.uid) } }
    private var sourceList: SoundInputSourceList {
        SoundInputSourceList(call: call, devices: physicalInputs,
            applications: mixer.apps.map { ($0.id, $0.name, !$0.processes.isEmpty) })
    }
    var body: some View {
        let list = sourceList
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
            VStack(spacing: 8) {
                SoundInputSourceRow(name: L10n.t(.soundSystemDefault, lang),
                    detail: physicalInputs.first(where: { $0.uid == sound.inputUID })?.name ?? L10n.t(.soundNoDevice, lang),
                    settings: call.microphone, enabled: controlsActive,
                    available: physicalInputs.contains { $0.uid == sound.inputUID }, lang: lang, edit: call.editMicrophone)
                ForEach(list.primary) { source in row(source) }
                if !list.other.isEmpty || !list.hidden.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            otherExpanded.toggle()
                            if !otherExpanded { restoring = false }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: otherExpanded ? "chevron.down" : "chevron.right").font(.system(size: 9))
                                Text(L10n.t(.soundOtherSources, lang)).font(Theme.mono(10)).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(String(list.other.count)).font(Theme.mono(10))
                                    .foregroundStyle(otherHovering ? Theme.textPrimary : Theme.textTertiary)
                            }.foregroundStyle(otherHovering ? Theme.textPrimary : Theme.textSecondary)
                                .padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain).onHover { otherHovering = $0 }.handCursor()
                            .accessibilityIdentifier("sound.input.otherSources")
                            .accessibilityValue(otherExpanded ? "1" : "0")
                        if otherExpanded, !list.hidden.isEmpty {
                            Button { restoring.toggle() } label: {
                                Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Theme.textSecondary).frame(width: 20, height: 28)
                            }.buttonStyle(.plain).hoverHighlight(5)
                                .accessibilityLabel(L10n.t(.soundHiddenSources, lang))
                                .popover(isPresented: $restoring, arrowEdge: .bottom) { hiddenSources(list.hidden) }
                        }
                    }
                    if otherExpanded { ForEach(list.other) { source in row(source) } }
                }
            }.transaction { $0.animation = nil; $0.disablesAnimations = true }
            if let failure = call.failure {
                let key: L10nKey = switch failure {
                case .permission: .soundPermission
                case .inputChanged: .soundInputChanged
                case .inputRemoval: .soundFailed
                default: .soundCallFailed
                }
                Text(L10n.t(key, lang))
                    .font(Theme.mono(10)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }.help(L10n.t(.soundCallCloseHint, lang))
            .onChange(of: list.hidden.map(\.id)) { _, ids in if ids.isEmpty { restoring = false } }
    }
    private func row(_ source: SoundInputListSource) -> some View {
        let settings: SoundChannelSettings
        let included: Bool
        switch source.id {
        case .device(let uid): settings = call.microphoneSettings(uid: uid); included = call.microphone.active && uid == sound.inputUID
        case .application(let id): settings = call.settings(id); included = false
        }
        let detail: String? = included ? L10n.t(.soundInputIncluded, lang)
            : !source.available ? L10n.t(.soundNoDevice, lang)
            : source.isVirtual ? L10n.t(.soundVirtualDevice, lang) : nil
        return SoundInputSourceRow(name: source.displayName(lang), detail: detail, settings: settings, enabled: controlsActive,
            available: source.available, included: included, pinned: call.sourceList.pinned.contains(source.id), lang: lang,
            edit: { change in
                switch source.id {
                case .device(let uid): call.editMicrophone(uid: uid, change)
                case .application(let id): call.editApplication(id, change)
                }
            }, pin: { call.setSourcePinned(!call.sourceList.pinned.contains(source.id), source: source.id, name: source.name) },
            hide: { _ = call.setSourceHidden(true, source: source.id, name: source.name) })
    }
    func hiddenSources(_ sources: [SoundInputListSource]) -> some View {
        SoundDeviceChoices {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t(.soundHiddenSources, lang)).font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Divider()
                ForEach(sources) { source in
                    HStack(spacing: 8) {
                        Text(source.displayName(lang)).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                            .lineLimit(2).help(source.displayName(lang))
                        Spacer(minLength: 0)
                        SettingChip(active: false, action: {
                            _ = call.setSourceHidden(false, source: source.id, name: source.name)
                        }) {
                            Label(L10n.t(.soundSourceRestore, lang), systemImage: "eye").font(Theme.mono(10))
                        }.fixedSize()
                    }
                }
            }.padding(12)
        }
    }
}
