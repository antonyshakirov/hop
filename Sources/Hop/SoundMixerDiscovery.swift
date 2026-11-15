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

struct SoundProcessMetadataCache {
    private struct Entry {
        let launch: Date
        let value: SoundMixerAppSnapshot
    }
    private var entries: [pid_t: Entry] = [:]

    mutating func value(pid: pid_t, launch: Date?, running: Bool,
                        load: () -> SoundMixerAppSnapshot?) -> SoundMixerAppSnapshot? {
        if let launch, let saved = entries[pid], saved.launch == launch {
            var value = saved.value
            value.appRunning = running
            return value
        }
        let value = load()
        if let launch, let value { entries[pid] = Entry(launch: launch, value: value) }
        else { entries[pid] = nil }
        return value
    }

    mutating func retain(_ pids: Set<pid_t>) { entries = entries.filter { pids.contains($0.key) } }
}

@MainActor
enum SoundMixerDiscovery {
    private static var metadataCache = SoundProcessMetadataCache()

    static func allowsApplication(_ id: String) -> Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !id.hasPrefix("com.antonshakirov.minimo") && !id.hasPrefix("com.antonshakirov.hop")
            && id != "systemsoundserverd" && id != "com.apple.systemsoundserverd"
    }
    static func applications() -> [SoundMixerAppSnapshot] {
        guard #available(macOS 14.2, *) else { return [] }
        let applications = NSWorkspace.shared.runningApplications
        var metadata: [pid_t: SoundMixerAppSnapshot] = [:]
        var seen = Set<pid_t>()
        defer { metadataCache.retain(seen) }
        var running: [SoundMixerAppSnapshot] = []
        for application in applications {
            seen.insert(application.processIdentifier)
            if let value = cachedMetadata(application) {
                metadata[application.processIdentifier] = value
                running.append(value)
            }
        }
        var groups: [String: SoundMixerAppSnapshot] = [:]
        for object in SoundHAL.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            guard let pid = SoundHAL.value(object, kAudioProcessPropertyPID, pid_t(0)),
                  pid != ProcessInfo.processInfo.processIdentifier else { continue }
            seen.insert(pid)
            if metadata[pid] == nil, let application = NSRunningApplication(processIdentifier: pid) {
                metadata[pid] = cachedMetadata(application)
            }
            let process = metadata[pid]
            guard let bundle = process?.id ?? SoundHAL.string(object, kAudioProcessPropertyBundleID),
                  !bundle.isEmpty, !bundle.hasPrefix("com.antonshakirov.minimo"),
                  !bundle.hasPrefix("com.antonshakirov.hop") else { continue }
            let owner = owningApplication(bundle: bundle, candidates: running) ?? process
            let id = owner?.id ?? bundle
            var app = groups[id] ?? SoundMixerAppSnapshot(id: id, name: owner?.name ?? id,
                processes: [], appRunning: owner?.appRunning ?? false, sourceRunning: false, iconURL: owner?.iconURL)
            app.processes.append(object)
            app.sourceRunning = app.sourceRunning || SoundHAL.value(object, kAudioProcessPropertyIsRunningOutput, UInt32(0)) == 1
            groups[id] = app
        }
        return merging(audio: Array(groups.values), running: running)
    }
    private static func cachedMetadata(_ application: NSRunningApplication) -> SoundMixerAppSnapshot? {
        metadataCache.value(pid: application.processIdentifier, launch: application.launchDate,
            running: !application.isTerminated, load: { snapshot(application) })
    }

    private static func snapshot(_ application: NSRunningApplication) -> SoundMixerAppSnapshot? {
        guard let id = application.bundleIdentifier else { return nil }
        return SoundMixerAppSnapshot(id: id, name: application.localizedName ?? id, processes: [],
            appRunning: !application.isTerminated, sourceRunning: false, iconURL: application.bundleURL)
    }

    // SPEC: docs/spec.md — match ownership from process identity, checking live audio flags each scan.
    static func owningApplication(bundle: String, candidates: [SoundMixerAppSnapshot]) -> SoundMixerAppSnapshot? {
        candidates.filter { !$0.id.isEmpty && (bundle == $0.id || bundle.hasPrefix($0.id + ".")) }
            .min { $0.id.count < $1.id.count }
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
