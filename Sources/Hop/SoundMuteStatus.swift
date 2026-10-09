import Combine
import HopCore

/// SPEC: docs/spec.md — "Sound": mute remains visible with the device window closed.
@MainActor
final class SoundMuteStatus: ObservableObject {
    @Published private(set) var outputMuted = false
    @Published private(set) var inputMuted = false
    private let hardware: SoundHardware
    private var watching = false

    init(hardware: SoundHardware? = nil) { self.hardware = hardware ?? CoreSoundHardware() }

    func setEnabled(_ enabled: Bool) {
        guard enabled != watching else { return }
        watching = enabled
        if enabled {
            refresh()
            hardware.watchMute { [weak self] in self?.refresh() }
        } else {
            hardware.unwatch()
            outputMuted = false
            inputMuted = false
        }
    }

    func refresh() {
        guard watching else { return }
        let output = hardware.devices(.output).first { $0.uid == hardware.defaultUID(.output) }?.muted == true
        let input = hardware.devices(.input).first { $0.uid == hardware.defaultUID(.input) }?.muted == true
        if output != outputMuted { outputMuted = output }
        if input != inputMuted { inputMuted = input }
    }
}
