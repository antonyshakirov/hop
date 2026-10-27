import Combine
import Foundation

@MainActor
final class SoundInputCoordinator {
    private let sound: SoundController
    private let mixer: SoundMixerController
    private let call: SoundCallMixController
    private let enabled: () -> Bool
    private var subscriptions: [AnyCancellable] = []
    private var observing = false
    private var preparing = false

    init(sound: SoundController, mixer: SoundMixerController, call: SoundCallMixController,
         enabled: @escaping () -> Bool) {
        self.sound = sound; self.mixer = mixer; self.call = call; self.enabled = enabled
        call.prepareInputSources = { [weak self] uid in
            guard let self else { return .failure(.unsupported) }
            return self.prepareInputSources(uid)
        }
        call.finishInputPreparation = { [weak self] in
            guard let self else { return }
            self.observeInput(self.call.running || self.call.starting)
        }
        subscriptions.append(sound.$inputInventory.removeDuplicates().sink { [weak call] inventory in
            call?.inputsChanged(defaultUID: inventory.uid, devices: inventory.devices)
        })
        subscriptions.append(mixer.$apps.sink { [weak call] apps in call?.sourcesChanged(apps) })
        subscriptions.append(mixer.$sourceRevision.dropFirst().sink { [weak call, weak mixer] _ in
            if let mixer { call?.sourcesChanged(mixer.apps) }
        })
        subscriptions.append(call.$running.combineLatest(call.$starting).sink { [weak self] running, starting in
            self?.observeInput(running || starting)
        })
        subscriptions.append(NotificationCenter.default.publisher(for: ModuleActivation.didChange).sink { [weak self] _ in
            guard let self, !self.enabled() else { return }
            self.call.stop()
            self.observeInput(false)
        })
    }

    func startQuickInput() {
        guard enabled(), call.enabled, !call.running, !call.starting else { return }
        preparing = true
        observeInput(true)
        sound.stopCheck(); sound.discardRecording()
        call.startQuick(inputUID: sound.inputUID, apps: mixer.apps)
        preparing = false
        observeInput(call.running || call.starting)
    }

    private func prepareInputSources(_ uid: String?) -> Result<[SoundMixerChannel], SoundFailure> {
        guard enabled() else { return .failure(.unsupported) }
        let wasPreparing = preparing
        preparing = true
        observeInput(true)
        preparing = wasPreparing
        guard enabled() else {
            observeInput(false)
            return .failure(.unsupported)
        }
        if let uid, uid != sound.inputUID {
            observeInput(false)
            return .failure(.inputChanged)
        }
        return .success(mixer.apps)
    }

    private func observeInput(_ active: Bool) {
        guard !Snapshot.active else { return }
        if active {
            guard enabled(), !observing else { return }
            observing = true
            sound.beginInputObservation()
            mixer.beginInputObservation()
        } else {
            guard !preparing, observing else { return }
            observing = false
            sound.endInputObservation()
            mixer.endInputObservation()
        }
    }
}
