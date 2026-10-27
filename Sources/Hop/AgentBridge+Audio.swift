import Foundation
import Combine
import HopCore

extension AgentBridge {
    func performAudio(_ command: AgentAudioCommand, on model: AppModel,
                      completed: @escaping (AgentResultV2) -> Void) {
        let sound = model.sound, mixer = model.soundMixer, call = model.soundCallMix
        func edited(_ settings: inout SoundChannelSettings, _ patch: AgentAudioCommand.Settings) {
            if let gain = patch.gain { settings.gain = gain }
            if let muted = patch.muted { settings.muted = muted }
            if let active = patch.active { settings.active = active }
        }
        func done(_ result: AgentResultV2) { completed(result) }
        switch command {
        case .volume(let direction, let value):
            sound.refresh()
            guard let device = sound.device(direction), device.canChangeVolume else { done(.rejected("audio_volume_unavailable")); return }
            Task { @MainActor in
                do { try await sound.setAgentVolume(value, direction: direction, expectedUID: device.uid); done(.applied()) }
                catch { done(.indeterminate()) }
            }
        case .mute(let direction, let muted):
            sound.refresh()
            guard let device = sound.device(direction), device.canMute else { done(.rejected("audio_mute_unavailable")); return }
            if device.muted == muted { done(.noChange()); return }
            Task { @MainActor in
                do { try await sound.setAgentMute(muted, direction: direction, expectedUID: device.uid); done(.applied()) }
                catch { done(.indeterminate()) }
            }
        case .device(let direction, let uid):
            sound.refresh()
            let devices = direction == .input ? sound.inputs : sound.outputs
            guard uid == "system" || devices.contains(where: { $0.uid == uid }) else { done(.rejected("audio_device_not_found")); return }
            guard direction != .input || uid == "system" || SoundInputMixPreferences.allowsMicrophone(uid) else { done(.rejected("audio_input_device_forbidden")); return }
            Task { @MainActor in
                do { try await sound.selectAgentDevice(uid, direction: direction); done(.applied()) }
                catch { done(.indeterminate()) }
            }
        case .outputMixer(let enabled):
            guard mixer.available else { done(.rejected("audio_mixer_unavailable")); return }
            if enabled == mixer.running && enabled == mixer.requested { done(.noChange()); return }
            if enabled { mixer.start() } else { mixer.stop() }
            done(mixer.failure == nil && mixer.running == enabled ? .applied() : .rejected("audio_mixer_failed"))
        case .application(let id, let patch, let uid):
            mixer.refreshForAgent()
            guard let app = mixer.apps.first(where: { $0.id == id }) else { done(.rejected("audio_app_not_found")); return }
            if let uid, uid != "system", !mixer.outputDevices.contains(where: { $0.uid == uid }) { done(.rejected("audio_device_not_found")); return }
            mixer.update(app) { edited(&$0, patch) }
            if let uid { mixer.selectOutput(app, uid: uid == "system" ? nil : uid) }
            done(.applied())
        case .addApplication(let id, let name):
            mixer.refreshForAgent()
            guard SoundMixerDiscovery.allowsApplication(id) else { done(.rejected("audio_app_forbidden")); return }
            mixer.addApplication(id: id, name: name); done(.applied())
        case .pinApplication(let id, let pinned):
            mixer.refreshForAgent()
            guard let app = mixer.apps.first(where: { $0.id == id }) else { done(.rejected("audio_app_not_found")); return }
            if app.preference.pinned == pinned { done(.noChange()); return }
            mixer.togglePin(app); done(.applied())
        case .moveApplication(let id, let offset):
            mixer.refreshForAgent()
            guard let app = mixer.apps.first(where: { $0.id == id }) else { done(.rejected("audio_app_not_found")); return }
            guard mixer.canMove(app, by: offset) else { done(.rejected("audio_order_boundary")); return }
            mixer.move(app, by: offset); done(.applied())
        case .resetApplications:
            mixer.resetApplicationAudio(); done(.applied())
        case .inputMixer(let enabled):
            guard call.enabled else { done(.rejected("audio_input_mixer_unavailable")); return }
            if !enabled {
                call.stopConfirmed { result in
                    switch result {
                    case .success: done(.applied())
                    case .failure: done(.indeterminate())
                    }
                }
                return
            }
            guard !call.stopping else { done(.rejected("audio_input_busy")); return }
            if call.running { done(.noChange()); return }
            guard !call.starting, !call.requestingMicrophone, !call.stopping else { done(.rejected("audio_input_busy")); return }
            awaitInput(call, start: { model.startQuickInput() }, completed: done)
        case .inputSource(let source, let id, let patch):
            guard !call.starting, !call.requestingMicrophone, !call.stopping else { done(.rejected("audio_input_busy")); return }
            func matches(_ value: SoundChannelSettings) -> Bool {
                (patch.gain == nil || value.gain == patch.gain) && (patch.muted == nil || value.muted == patch.muted) && (patch.active == nil || value.active == patch.active)
            }
            let edit: () -> Void
            let verify: () -> Bool
            switch source {
            case .system:
                edit = { call.editMicrophone(uid: nil) { edited(&$0, patch) } }
                verify = { matches(call.microphone) }
            case .device:
                guard let id else { done(.rejected("audio_device_not_found")); return }
                let inventory = sound.agentInventorySnapshot()
                guard SoundInputMixPreferences.allowsMicrophone(id), inventory.inputs.contains(where: { $0.uid == id }) else { done(.rejected("audio_device_not_found")); return }
                guard !call.microphone.active || (inventory.inputUID != id && call.systemInputUID != id) else { done(.rejected("audio_source_included_via_system")); return }
                edit = { call.editMicrophone(uid: id) { edited(&$0, patch) } }
                verify = { call.microphones[id].map(matches) ?? false }
            case .app:
                mixer.refreshForAgent()
                guard let id, SoundCallMixPolicy.allows(id), mixer.apps.contains(where: { $0.id == id }) else { done(.rejected("audio_app_not_found")); return }
                edit = { call.editApplication(id) { edited(&$0, patch) } }
                verify = { matches(call.settings(id)) }
            }
            if call.running { awaitInput(call, start: edit, verify: verify, completed: done) }
            else { edit(); done(verify() ? .applied() : .rejected("audio_input_update_failed")) }

        }
    }

    private func awaitInput(_ controller: SoundCallMixController, start: () -> Void, verify: @escaping () -> Bool = { true },
                            completed: @escaping (AgentResultV2) -> Void) {
        let wait = AgentInputReadiness(controller: controller, verify: verify, completed: completed)
        wait.begin(start, timeout: audioAcknowledgementTimeout)
    }

    func audioState(_ model: AppModel) -> [String: Any] {
        let sound = model.sound, mixer = model.soundMixer, call = model.soundCallMix
        let inventory = sound.agentInventorySnapshot()
        let applications = mixer.agentApplicationInventory()
        var preset = SoundInputMixPreferences(); preset.system = call.microphone; preset.microphones = call.microphones
        let requested = preset.resolvedInputs(defaultUID: inventory.inputUID, availableUIDs: Set(inventory.inputs.map(\.uid)))
        func settings(_ value: SoundChannelSettings) -> [String: Any] { ["gain": value.safeGain, "muted": value.muted, "active": value.active] }
        func route(_ state: SoundAppRouteState) -> [String: Any] {
            switch state {
            case .stopped: return ["state": "stopped"]
            case .preparing: return ["state": "preparing"]
            case .waiting: return ["state": "waiting"]
            case .failed: return ["state": "failed"]
            case .playing(let uid): return ["state": "playing", "outputUID": uid]
            }
        }
        func devices(_ list: [SoundDevice]) -> [[String: Any]] {
            list.map { device in
                var out: [String: Any] = ["uid": device.uid, "name": device.name, "canChangeVolume": device.canChangeVolume, "canMute": device.canMute]
                if let volume = device.volume { out["volume"] = volume }
                if let muted = device.muted { out["muted"] = muted }
                return out
            }
        }
        return ["inventoryFreshness": "snapshot", "outputs": devices(inventory.outputs), "inputs": devices(inventory.inputs),
            "availableApplications": applications.map { ["appID": $0.id, "name": $0.name, "appRunning": $0.appRunning, "sourceRunning": $0.sourceRunning] },
            "outputUID": inventory.outputUID as Any? ?? NSNull(), "inputUID": inventory.inputUID as Any? ?? NSNull(),
            "outputFollowsSystem": sound.outputFollowsSystem, "inputFollowsSystem": sound.inputFollowsSystem,
            "outputMixer": ["available": mixer.available, "requested": mixer.requested, "running": mixer.running, "starting": mixer.starting,
                "runningMeaning": "routing_session_created_not_audible_playback", "failed": mixer.failure != nil,
                "applications": mixer.apps.map { app -> [String: Any] in
                    ["appID": app.id, "name": app.name, "gain": app.settings.safeGain, "muted": app.settings.muted,
                     "outputUID": app.preference.outputUID ?? "system", "pinned": app.preference.pinned,
                     "appRunning": app.appRunning, "routeState": route(app.routeState)]
                }],
            "inputMixer": ["available": call.enabled, "microphoneOverlayMuted": call.accessoryMuted, "running": call.running, "starting": call.starting, "stopping": call.stopping, "requestingMicrophone": call.requestingMicrophone,
                "updating": call.updating, "configurationRevision": call.configurationRevision, "appliedConfigurationRevision": call.appliedConfigurationRevision,
                "failed": call.failure != nil, "savedSettingsDoNotImplyCapture": true, "system": settings(call.microphone),
                "effectiveInputUIDs": call.effectiveInputUIDs, "effectiveApplicationIDs": call.effectiveApplicationIDs,
                "requestedPhysicalInputs": requested.map { ["deviceUID": $0.uid, "settings": settings($0.settings)] },
                "devices": call.microphones.mapValues(settings), "applications": call.applications.mapValues(settings)]]
    }
}

@MainActor
private final class AgentInputReadiness {
    private let controller: SoundCallMixController
    private var completed: ((AgentResultV2) -> Void)?
    private let verify: () -> Bool
    private var observation: AnyCancellable?
    private var timeout: Task<Void, Never>?
    private var generation: Int?
    init(controller: SoundCallMixController, verify: @escaping () -> Bool, completed: @escaping (AgentResultV2) -> Void) {
        self.controller = controller; self.verify = verify; self.completed = completed
    }
    func begin(_ start: () -> Void, timeout duration: Duration) {
        observation = controller.objectWillChange.sink { [self] _ in Task { @MainActor in evaluate() } }
        start()
        generation = controller.sessionGeneration
        timeout = Task { @MainActor [self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard generation == controller.sessionGeneration else { finish(.rejected("audio_input_start_cancelled")); return }
            controller.stop()
            finish(.indeterminate())
        }
        evaluate()
    }
    private func evaluate() {
        guard let generation else { return }
        guard generation == controller.sessionGeneration else { finish(.rejected("audio_input_start_cancelled")); return }
        if let failure = controller.failure {
            let code: String
            switch failure {
            case .permission: code = "audio_microphone_permission_denied"
            case .missingDevice: code = "audio_device_not_found"
            case .inputChanged: code = "audio_input_changed"
            case .unsupported: code = "audio_input_unsupported"
            case .system: code = "audio_input_failed"
            }
            finish(.rejected(code))
        }
        else if controller.running && !controller.starting && !controller.requestingMicrophone && !controller.updating && controller.appliedConfigurationRevision >= controller.configurationRevision {
            finish(verify() ? .applied() : .indeterminate())
        }
        else if !controller.running && !controller.starting && !controller.requestingMicrophone { finish(.rejected("audio_input_start_cancelled")) }
    }
    private func finish(_ result: AgentResultV2) {
        guard let completed else { return }
        self.completed = nil; observation = nil; timeout?.cancel(); timeout = nil
        completed(result)
    }
}
