import AppKit
import HopCore
import SwiftUI

/// SPEC: docs/spec.md — "Sound": the thumb follows the pointer, independent of hardware acknowledgement.
struct SoundVolumeControl: View {
    let device: SoundDevice
    let direction: SoundDirection
    let lang: AppLanguage
    var set: (Double) -> Void
    let maximum: Double
    let label: L10nKey
    let showLabel: Bool
    @State private var volumeEditing: SoundVolumeEditing
    @State private var editing = false
    @State private var percentageEditing = false
    @State private var enteringPercentage = false
    @Environment(\.isEnabled) private var controlsEnabled

    init(device: SoundDevice, direction: SoundDirection, lang: AppLanguage,
         maximum: Double = 1, label: L10nKey = .soundVolume, showLabel: Bool = true, set: @escaping (Double) -> Void) {
        self.device = device; self.direction = direction; self.lang = lang; self.set = set
        self.maximum = maximum; self.label = label; self.showLabel = showLabel
        _volumeEditing = State(initialValue: SoundVolumeEditing(value: device.volume ?? 0))
    }

    private var controlName: String {
        label == .soundMixerGain ? device.name : L10n.t(direction == .input ? .soundInput : .soundOutput, lang)
    }

    var body: some View {
        HStack(spacing: 12) {
            if showLabel { Text(L10n.t(label, lang)).font(Theme.mono(11)).foregroundStyle(controlsEnabled ? Theme.textTertiary : Theme.disabledForeground) }
            MiniSlider(value: Binding(get: { Int((volumeEditing.value * 100).rounded()) }, set: {
                let value = Double($0) / 100
                volumeEditing.drag(to: value)
                enteringPercentage = false
                set(value)
            }), range: 0...Int(maximum * 100), width: nil, showsNumber: false,
                       accessibilityName: controlName + " " + L10n.t(label, lang),
                       subdued: device.muted == true, onEditingChanged: { editing = $0 })
            HStack(spacing: 2) {
                if Snapshot.active || !controlsEnabled || !percentageEditing {
                    if controlsEnabled && !Snapshot.active {
                        Button { volumeEditing.begin(); percentageEditing = true } label: {
                            Text("\(Int((volumeEditing.value * 100).rounded()))%")
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(controlName + " %")
                    } else {
                        Text("\(Int((volumeEditing.value * 100).rounded()))%")
                    }
                } else {
                    SteadyField(text: $volumeEditing.text, size: 11, weight: .medium,
                                alignment: .right, colour: Theme.textSecondary, focus: $enteringPercentage,
                                onSubmit: { percentageEditing = false },
                                onCancel: { volumeEditing.cancel(); percentageEditing = false },
                                onOutsideInteraction: { percentageEditing = false })
                        .frame(width: 34, height: 14)
                        .accessibilityLabel(controlName + " %")
                        .onAppear { enteringPercentage = true }
                    Text("%")
                }
            }
            .font(Theme.mono(11)).foregroundStyle(controlsEnabled ? Theme.textSecondary : Theme.disabledForeground)
            .frame(width: 44, alignment: .trailing)
            .onHover { hovering in if !hovering { percentageEditing = false } }
            .onChange(of: enteringPercentage) { _, focused in if !focused { percentageEditing = false } }
            .onChange(of: percentageEditing) { _, editing in
                if !editing {
                    enteringPercentage = false
                    if let value = volumeEditing.commit(maximum: maximum) { set(value) }
                }
            }
            .onChange(of: controlsEnabled) { _, enabled in if !enabled { percentageEditing = false } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in percentageEditing = false }
        }

        .onChange(of: device.volume) { _, volume in
            if !editing, !percentageEditing, let volume {
                volumeEditing.reflect(volume)
            }
        }
    }
}

private struct SoundDeviceMenu: View {
    let direction: SoundDirection
    let lang: AppLanguage
    @ObservedObject var sound: SoundController
    @State private var presented = false

    private var follows: Bool { direction == .output ? sound.outputFollowsSystem : sound.inputFollowsSystem }
    private var current: SoundDevice? { sound.device(direction) }
    private var devices: [SoundDevice] { direction == .output ? sound.outputs : sound.inputs }
    private var title: String {
        follows ? L10n.t(.soundSystemDefault, lang) + " · " + (current?.name ?? L10n.t(.soundNoDevice, lang))
                : current?.name ?? L10n.t(.soundNoDevice, lang)
    }

    var body: some View {
        SettingChip(active: presented, action: { presented.toggle() }) {
            HStack(spacing: 7) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(Theme.mono(9))
            }.font(Theme.mono(10))
        }
            .accessibilityLabel(L10n.t(direction == .input ? .soundInput : .soundOutput, lang))
            .accessibilityValue(title)
            .help(L10n.t(.soundDefaultHint, lang))
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                SoundDeviceChoices {
                    VStack(alignment: .leading, spacing: 0) {
                        choice(L10n.t(.soundSystemDefault, lang), uid: "", selected: follows)
                        Divider().padding(.vertical, 3)
                        ForEach(devices) { device in
                            choice(device.name, uid: device.uid, selected: !follows && device.uid == current?.uid)
                        }
                    }.padding(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func choice(_ title: String, uid: String, selected: Bool) -> some View {
        SoundDeviceChoiceRow(title: title, selected: selected) {
            sound.select(uid, direction: direction)
            presented = false
        }
    }
}

private struct SoundElapsed: View {
    @ObservedObject var readings: SoundLiveReadings
    let lang: AppLanguage
    var body: some View {
        Text(String(format: "%.1f %@", readings.duration, L10n.t(.unitSec, lang)))
            .font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
    }
}

private struct SoundLiveMeter: View {
    @ObservedObject var readings: SoundLiveReadings
    let lang: AppLanguage
    var body: some View { SoundInputMeter(level: readings.level, peak: readings.peak, lang: lang) }
}

/// SPEC: docs/spec.md — "Sound": a segmented dB meter, never a volume slider.
struct SoundInputMeter: View {
    let level: Double
    let peak: Double
    let lang: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.t(.soundLevel, lang), systemImage: "waveform").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int((level * 60 - 60).rounded())) dBFS").foregroundStyle(Theme.textTertiary)
            }.font(Theme.mono(10))
            HStack(spacing: 3) {
                ForEach(0..<30, id: \.self) { index in
                    let color: Color = index >= 28 ? .red : index >= 24 ? .yellow : .green
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Double(index) / 30 < level ? color : color.opacity(0.12))
                        .overlay(alignment: .top) {
                            if index == min(29, Int(peak * 30)), peak > 0 {
                                Rectangle().fill(Theme.textPrimary).frame(height: 2)
                            }
                        }
                }
            }.frame(height: 22)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t(.soundLevel, lang))
                .accessibilityValue("\(Int((level * 60 - 60).rounded())) dBFS")
            HStack {
                Text("−60")
                Spacer(); Text("−30")
                Spacer(); Text("−12")
                Spacer(); Text("0 dB")
            }.font(Theme.mono(9)).foregroundStyle(Theme.textTertiary)
        }
    }
}

struct SoundWindowView: View {
    @ObservedObject var sound: SoundController
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @EnvironmentObject var model: AppModel
    private enum Page: CaseIterable {
        case output, input
        var key: L10nKey { switch self { case .output: .soundOutput; case .input: .soundInput } }
    }
    @State private var page: Page = .output
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    init(sound: SoundController, initialInput: Bool = false, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.sound = sound; self.onHeightChange = onHeightChange
        _page = State(initialValue: initialInput ? .input : .output)
    }
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        VStack(spacing: 0) {
            navigation
            Group {
                if Snapshot.active { content }
                else { ScrollView { content } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panelBackground)
        .id(model.themeVersion)
        .onPreferenceChange(SoundWindowHeightPreference.self) { height in
            if height.navigation > 0, height.content > 0 { onHeightChange(height.navigation + height.content) }
        }
        .onChange(of: page) { old, _ in if old == .input { sound.stopCheck() } }
        .onChange(of: model.soundPageRequest, initial: true) { _, request in
            guard let request else { return }
            page = request == .input ? .input : .output
            model.soundPageRequest = nil
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t(.soundLabel)).font(Theme.mono(13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 2) {
                    ForEach(Page.allCases, id: \.self) { candidate in
                        SpaceTabButton(icon: candidate == .output ? "speaker.wave.2" : "mic",
                                       title: t(candidate.key), active: page == candidate) { page = candidate }
                            .accessibilityIdentifier("sound.tab." + String(describing: candidate))
                            .accessibilityValue(page == candidate ? "1" : "0")
                    }
                }
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.divider, lineWidth: 1))
            }.padding(.horizontal, 20).padding(.top, 12)
            Divider()
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: SoundWindowHeightPreference.self, value: .init(navigation: proxy.size.height))
        })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                switch page {
                case .output:
                    VStack(alignment: .leading, spacing: 20) {
                        section(.output)
                        Divider()
                        SoundMixerChannels(mixer: model.soundMixer, lang: lang)
                    }
                case .input:
                    VStack(alignment: .leading, spacing: 16) {
                        section(.input)
                        if sound.device(.input)?.muted == true {
                            Text(t(.soundCurrentMicOnly)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if model.soundCallMix.enabled {
                            Divider()
                            SoundCallMixView(call: model.soundCallMix, sound: sound, mixer: model.soundMixer, lang: lang,
                                initiallyExpanded: Snapshot.active && CommandLine.arguments.contains("--sound-sources-expanded"))
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
            if let failure = sound.failure {
                Text(failureText(failure)).font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if failure == .permission {
                    action(.permGrant, icon: "gearshape") {
                        if let url = URL(string: MicrophoneLevelMeter.privacySettingsURL) { NSWorkspace.shared.open(url) }
                    }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SoundWindowHeightPreference.self, value: .init(content: proxy.size.height))
            })
    }

    private func failureText(_ failure: SoundFailure) -> String {
        switch failure {
        case .permission: return t(.soundPermission)
        case .unsupported: return t(.soundMuteUnavailable)
        case .missingDevice: return t(.soundNoDevice)
        case .inputChanged: return t(.soundInputChanged)
        case .system: return t(.soundFailed)
        }
    }

    @ViewBuilder private func section(_ direction: SoundDirection) -> some View {
        let current = sound.device(direction)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label(t(direction == .output ? .soundOutput : .soundInput),
                      systemImage: direction == .output ? "speaker.wave.2" : "mic")
                    .font(Theme.mono(11, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                SoundDeviceMenu(direction: direction, lang: lang, sound: sound)
            }
            if let current {
                HStack(spacing: 12) {
                    if current.volume != nil, current.canChangeVolume {
                        SoundVolumeControl(device: current, direction: direction, lang: lang,
                            label: direction == .output ? .soundMacVolume : .soundVolume) {
                            sound.setVolume($0, direction: direction, expectedUID: current.uid)
                        }.id(current.uid).frame(maxWidth: .infinity)
                    } else {
                        Text(t(.soundVolumeUnavailable)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if current.canMute, let muted = current.muted {
                        deviceMuteButton(current, direction: direction, muted: muted)
                    } else {
                        Text(t(.soundMuteUnavailable)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if direction == .input {
                HStack(spacing: 12) {
                    action(sound.checking || sound.requestingAccess ? .soundStopMic : .soundCheckMic,
                           icon: sound.checking || sound.requestingAccess ? "stop.circle" : "mic.circle") {
                        if sound.checking || sound.requestingAccess { sound.stopCheck() }
                        else { sound.startCheck() }
                    }.disabled(current == nil || model.soundCallMix.running || model.soundCallMix.starting)
                    if sound.checking {
                        SettingChip(active: sound.checkMuted, action: sound.toggleCheckMute) {
                            HStack(spacing: 6) {
                                Text("Hop")
                                SoundMuteLabel(muted: sound.checkMuted, input: true, lang: lang)
                            }.font(Theme.mono(10))
                        }.accessibilityLabel("Hop: " + t(sound.checkMuted ? .soundUnmute : .soundMute))
                            .accessibilityValue(sound.checkMuted ? "1" : "0")
                    }
                    if sound.hasRecording {
                        action(sound.playing ? .soundStopPlayback : .soundListen, icon: sound.playing ? "stop.fill" : "play.fill") {
                            if sound.playing { sound.stopPlayback() } else { sound.playRecording() }
                        }
                    }
                    if sound.checking || sound.hasRecording {
                        SoundElapsed(readings: sound.readings, lang: lang)
                    }
                }.padding(.top, 8)
                if sound.checking { SoundLiveMeter(readings: sound.readings, lang: lang) }
                if !sound.checking, !sound.hasRecording {
                    Text(t(.soundSampleHint)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func deviceMuteButton(_ device: SoundDevice, direction: SoundDirection, muted: Bool) -> some View {
        SettingChip(active: muted, action: { sound.toggleMute(direction, expectedUID: device.uid) }) {
            SoundMuteLabel(muted: muted, input: direction == .input, lang: lang)
                .font(Theme.mono(10))
        }
        .help(device.name + ": " + t(muted ? .soundUnmute : .soundMute))
        .accessibilityLabel(device.name + ": " + t(muted ? .soundUnmute : .soundMute))
        .accessibilityValue(muted ? "1" : "0")
    }

    private func action(_ key: L10nKey, icon: String, perform: @escaping () -> Void) -> some View {
        SettingChip(active: key == .soundStopMic || key == .soundStopPlayback, action: perform) {
            Label(t(key), systemImage: icon).font(Theme.mono(10))
        }
    }
}

private struct SoundWindowMeasuredHeight: Equatable {
    var navigation: CGFloat = 0
    var content: CGFloat = 0
}

private struct SoundWindowHeightPreference: PreferenceKey {
    static var defaultValue = SoundWindowMeasuredHeight()
    static func reduce(value: inout SoundWindowMeasuredHeight, nextValue: () -> SoundWindowMeasuredHeight) {
        let next = nextValue()
        value.navigation = max(value.navigation, next.navigation)
        value.content = max(value.content, next.content)
    }
}

struct SoundMuteLabel: View {
    let muted: Bool
    let input: Bool
    let lang: AppLanguage
    private var icon: String { input ? "mic.slash.fill" : "speaker.slash.fill" }
    var body: some View {
        ZStack {
            Label(L10n.t(.soundMute, lang), systemImage: icon).hidden()
            Label(L10n.t(.soundUnmute, lang), systemImage: icon).hidden()
            Label(L10n.t(muted ? .soundUnmute : .soundMute, lang), systemImage: icon)
        }
    }
}
