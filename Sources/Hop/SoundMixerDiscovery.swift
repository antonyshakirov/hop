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
        return Array(groups.values)
    }
}
