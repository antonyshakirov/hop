import HopCore

final class SoundOutputHandoff {
    private let setSourceMuted: (Bool) throws -> Void
    private let setPlaybackEnabled: (Bool) -> Void
    private let releaseSource: () -> Void
    private let stopPlayback: () -> Void
    private let discardQueued: () -> Void
    private let fallbackSourceGuard: (() throws -> Void)?
    private var outputUID: String?
    private var guarded = false
    private var stopped = false
    private var prepared = false

    init(setSourceMuted: @escaping (Bool) throws -> Void,
         setPlaybackEnabled: @escaping (Bool) -> Void,
         releaseSource: @escaping () -> Void, stopPlayback: @escaping () -> Void,
         discardQueued: @escaping () -> Void, fallbackSourceGuard: (() throws -> Void)? = nil) {
        self.setSourceMuted = setSourceMuted; self.setPlaybackEnabled = setPlaybackEnabled
        self.releaseSource = releaseSource; self.stopPlayback = stopPlayback; self.discardQueued = discardQueued
        self.fallbackSourceGuard = fallbackSourceGuard
    }
    static func needsGuard(outputUID: String?, followsSystem: Bool, settings: SoundChannelSettings) -> Bool {
        outputUID == nil || !followsSystem || settings.muted || settings.safeGain == 0
    }
    var sourceGuarded: Bool { guarded }
    func prepare(outputUID: String?, followsSystem: Bool, settings: SoundChannelSettings) throws {
        guard !stopped else { return }
        setPlaybackEnabled(false); prepared = true
        self.outputUID = outputUID
        if Self.needsGuard(outputUID: outputUID, followsSystem: followsSystem, settings: settings) { try acquireGuard() }
        else if !guarded { try setSourceMuted(false) }
    }
    func reconcile(outputUID: String?, followsSystem: Bool, settings: SoundChannelSettings) throws {
        guard !stopped else { return }
        self.outputUID = outputUID
        if Self.needsGuard(outputUID: outputUID, followsSystem: followsSystem, settings: settings) { try acquireGuard() }
    }
    func acquireGuard() throws {
        guard !stopped, !guarded else { return }
        do { try setSourceMuted(true) }
        catch {
            setPlaybackEnabled(false)
            guard let fallbackSourceGuard else { throw error }
            try fallbackSourceGuard()
        }
        guarded = true
    }
    func ready(for uid: String) throws -> Bool {
        guard !stopped, prepared, outputUID == uid else { return false }
        try acquireGuard()
        setPlaybackEnabled(true)
        return true
    }
    func fail() throws {
        guard !stopped else { return }
        setPlaybackEnabled(false)
        defer { stopPlayback(); discardQueued() }
        try acquireGuard()
    }
    func stop() {
        guard !stopped else { return }
        stopped = true
        setPlaybackEnabled(false); releaseSource(); guarded = false
        stopPlayback(); discardQueued()
    }
}
