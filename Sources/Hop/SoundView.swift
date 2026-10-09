import AppKit
import HopCore
import SwiftUI

struct SoundRow: View {
    let lang: AppLanguage
    @ObservedObject var status: SoundMuteStatus
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                ModuleMarkIcon(symbol: "speaker.wave.2", color: Theme.textSecondary)
                Text(L10n.t(.soundLabel, lang)).font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 12)
                if status.outputMuted {
                    Image(systemName: "speaker.slash.fill").foregroundStyle(Theme.accentOrange)
                        .accessibilityLabel(L10n.t(.soundOutput, lang) + ": " + L10n.t(.soundMuted, lang))
                }
                if status.inputMuted {
                    Image(systemName: "mic.slash.fill").foregroundStyle(Theme.accentOrange)
                        .accessibilityLabel(L10n.t(.soundInput, lang) + ": " + L10n.t(.soundMuted, lang))
                }
                RowActionIcon(symbol: "slider.horizontal.3", compact: true)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverDim()
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
        .help(L10n.t(.soundOpen, lang))
    }
}

/// SPEC: docs/spec.md — "Sound": the thumb follows the pointer, independent of hardware acknowledgement.
struct SoundVolumeControl: View {
    let device: SoundDevice
    let direction: SoundDirection
    let lang: AppLanguage
    var set: (Double) -> Void
    let maximum: Double
    let label: L10nKey
    @State private var value: Double
    @State private var editing = false
    @State private var percentage = ""
    @State private var originalPercentage = ""
    @State private var cancelledPercentage = false
    @FocusState private var enteringPercentage: Bool

    init(device: SoundDevice, direction: SoundDirection, lang: AppLanguage,
         maximum: Double = 1, label: L10nKey = .soundVolume, set: @escaping (Double) -> Void) {
        self.device = device; self.direction = direction; self.lang = lang; self.set = set
        self.maximum = maximum; self.label = label
        _value = State(initialValue: device.volume ?? 0)
    }

    private var controlName: String {
        label == .soundMixerGain ? device.name : L10n.t(direction == .input ? .soundInput : .soundOutput, lang)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(L10n.t(label, lang)).font(Theme.mono(11)).foregroundStyle(Theme.textTertiary)
            if Snapshot.active {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.chipBg)
                        Capsule().fill(device.muted == true ? Theme.textTertiary : Theme.accentYellow)
                            .frame(width: geometry.size.width * value / maximum)
                    }.frame(height: 4).frame(maxHeight: .infinity)
                }.frame(height: 18)
            } else {
                Slider(value: Binding(get: { value }, set: { value = $0; set($0) }), in: 0...maximum,
                       onEditingChanged: { editing = $0 })
                    .tint(device.muted == true ? Theme.textTertiary : Theme.accentYellow)
                    .opacity(device.muted == true ? 0.45 : 1)
                    .accessibilityLabel(controlName + " " + L10n.t(label, lang))
            }
            if Snapshot.active {
                Text("\(Int((value * 100).rounded()))%")
                    .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    .fixedSize().frame(width: 42, alignment: .trailing)
            } else {
                HStack(spacing: 2) {
                    TextField("", text: $percentage).textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing).frame(width: 34)
                        .focused($enteringPercentage)
                        .accessibilityLabel(controlName + " %")
                        .onSubmit { enteringPercentage = false }
                        .onExitCommand { cancelledPercentage = true; enteringPercentage = false }
                    Text("%")
                }.font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    .onAppear { percentage = String(Int((value * 100).rounded())) }
                    .onChange(of: enteringPercentage) { _, focused in
                        if focused {
                            percentage = String(Int((value * 100).rounded()))
                            originalPercentage = percentage
                            cancelledPercentage = false
                        }
                        else {
                            if !cancelledPercentage, percentage != originalPercentage,
                               let parsed = SoundPercentage.value(percentage, maximum: maximum * 100) { value = parsed; set(parsed) }
                            percentage = String(Int((value * 100).rounded()))
                        }
                    }
            }
        }
        .onChange(of: device.volume) { _, volume in
            if !editing, !enteringPercentage, let volume {
                value = volume
                percentage = String(Int((value * 100).rounded()))
            }
        }
        .onChange(of: value) { _, value in if !enteringPercentage { percentage = String(Int((value * 100).rounded())) } }
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
        Button { presented.toggle() } label: {
            HStack(spacing: 7) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(Theme.mono(9))
            }.font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).hoverDim()
            .accessibilityLabel(L10n.t(direction == .input ? .soundInput : .soundOutput, lang))
            .accessibilityValue(title)
            .help(L10n.t(.soundDefaultHint, lang))
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        choice(L10n.t(.soundSystemDefault, lang), uid: "", selected: follows)
                        Divider().padding(.vertical, 4)
                        ForEach(devices) { device in
                            choice(device.name, uid: device.uid, selected: !follows && device.uid == current?.uid)
                        }
                    }.padding(8)
                }.frame(width: 300, height: min(320, CGFloat(devices.count + 1) * 36 + 28))
                    .background(Theme.panelBackground)
                    .hopLayoutDirection()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func choice(_ title: String, uid: String, selected: Bool) -> some View {
        Button {
            sound.select(uid, direction: direction)
            presented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : "circle")
                    .foregroundStyle(selected ? Theme.accentYellow : Theme.textTertiary)
                Text(title).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Spacer(minLength: 0)
            }.font(Theme.mono(11)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).hoverHighlight(5)
    }
}

private struct SoundContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
    @AppStorage(SettingsKey.appLanguage) private var languageRaw = "auto"
    private var lang: AppLanguage { L10n.resolve(languageRaw) }
    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        Group {
            if Snapshot.active { content }
            else { ScrollView { content } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.panelBackground)
        .id(model.themeVersion)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(t(.soundLabel)).font(Theme.mono(20)).foregroundStyle(Theme.textPrimary)
                Spacer()
                SoundMixerSwitch(mixer: model.soundMixer, lang: lang)
            }
            section(.output)
            SoundMixerChannels(mixer: model.soundMixer, input: false, lang: lang)
            Rectangle().fill(Theme.divider).frame(height: 1)
            section(.input)
            SoundMixerChannels(mixer: model.soundMixer, input: true, lang: lang)
            if sound.device(.input)?.muted == true {
                Text(t(.soundCurrentMicOnly)).font(Theme.mono(10))
                    .foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            if let failure = sound.failure {
                Text(failureText(failure)).font(Theme.mono(11))
                    .foregroundStyle(Theme.accentOrange).fixedSize(horizontal: false, vertical: true)
                if failure == .permission {
                    action(.permGrant, icon: "gearshape") {
                        if let url = URL(string: MicrophoneLevelMeter.privacySettingsURL) { NSWorkspace.shared.open(url) }
                    }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in Color.clear.preference(key: SoundContentHeight.self, value: proxy.size.height) })
            .onPreferenceChange(SoundContentHeight.self, perform: onHeightChange)
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
                    .font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                SoundDeviceMenu(direction: direction, lang: lang, sound: sound)
            }
            if let current {
                HStack(spacing: 12) {
                    if current.volume != nil, current.canChangeVolume {
                        SoundVolumeControl(device: current, direction: direction, lang: lang) {
                            sound.setVolume($0, direction: direction, expectedUID: current.uid)
                        }.id(current.uid).frame(maxWidth: .infinity)
                    } else {
                        Text(t(.soundVolumeUnavailable)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if current.canMute, let muted = current.muted {
                        action(muted ? .soundUnmute : .soundMute,
                               icon: direction == .input ? (muted ? "mic" : "mic.slash") : (muted ? "speaker.wave.2" : "speaker.slash")) {
                            sound.toggleMute(direction, expectedUID: current.uid)
                        }.help(muted ? t(.soundMuted) : t(.soundMute))
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
                    }.disabled(current == nil)
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

    private func action(_ key: L10nKey, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(t(key), systemImage: icon).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).hoverDim()
    }
}
