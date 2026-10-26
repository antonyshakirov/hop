import AppKit
import CoreAudio
import HopAudioEngine

struct SoundMixerAppSnapshot {
    var id: String
    var name: String
    var processes: [AudioObjectID]
    var appRunning: Bool
    var sourceRunning: Bool
    var iconURL: URL? = nil
}

@MainActor
enum SoundMixerDiscovery {
    static func allowsApplication(_ id: String) -> Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !id.hasPrefix("com.antonshakirov.minimo") && !id.hasPrefix("com.antonshakirov.hop")
            && id != "systemsoundserverd" && id != "com.apple.systemsoundserverd"
    }
    static func applications() -> [SoundMixerAppSnapshot] {
        guard #available(macOS 14.2, *) else { return [] }
        let applications = NSWorkspace.shared.runningApplications
        var groups: [String: SoundMixerAppSnapshot] = [:]
        for object in SoundHAL.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            guard let pid = SoundHAL.value(object, kAudioProcessPropertyPID, pid_t(0)),
                  pid != ProcessInfo.processInfo.processIdentifier else { continue }
            let processApp = NSRunningApplication(processIdentifier: pid)
            guard let bundle = processApp?.bundleIdentifier ?? SoundHAL.string(object, kAudioProcessPropertyBundleID),
                  !bundle.isEmpty, !bundle.hasPrefix("com.antonshakirov.minimo"),
                  !bundle.hasPrefix("com.antonshakirov.hop") else { continue }
            let owner = applications.filter {
                guard let key = $0.bundleIdentifier, !key.isEmpty else { return false }
                return bundle == key || bundle.hasPrefix(key + ".")
            }.min { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) } ?? processApp
            let id = owner?.bundleIdentifier ?? bundle
            var app = groups[id] ?? SoundMixerAppSnapshot(id: id, name: owner?.localizedName ?? id,
                processes: [], appRunning: owner?.isTerminated == false, sourceRunning: false, iconURL: owner?.bundleURL)
            app.processes.append(object)
            app.sourceRunning = app.sourceRunning || SoundHAL.value(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1
            groups[id] = app
        }
        let running = applications.compactMap { application -> SoundMixerAppSnapshot? in
            guard let id = application.bundleIdentifier, !application.isTerminated else { return nil }
            return SoundMixerAppSnapshot(id: id, name: application.localizedName ?? id, processes: [],
                appRunning: true, sourceRunning: false, iconURL: application.bundleURL)
        }
        return merging(audio: Array(groups.values), running: running)
    }
    static func merging(audio: [SoundMixerAppSnapshot], running: [SoundMixerAppSnapshot]) -> [SoundMixerAppSnapshot] {
        var groups = Dictionary(uniqueKeysWithValues: audio.filter { allowsApplication($0.id) }.map { ($0.id, $0) })
        for application in running where application.appRunning && allowsApplication(application.id) {
            if var existing = groups[application.id] {
                existing.appRunning = true
                if existing.iconURL == nil { existing.iconURL = application.iconURL }
                groups[application.id] = existing
            } else {
                var app = application
                app.processes = []; app.sourceRunning = false
                groups[app.id] = app
            }
        }
        return Array(groups.values)
    }
}
