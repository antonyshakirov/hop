import AppKit

/// All app sounds behind a single switch. System notifications
/// live separately — the app does not control their sound.
@MainActor
enum Sounds {
    static let enabledKey = "appSoundsEnabled" // enabled by default

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static var lastTick = Date.distantPast
    private static let tickBase = NSSound(named: "Tink")

    /// Strong references to playing sounds: without one, ARC could release
    /// a local NSSound BEFORE it played — the sound went missing "occasionally".
    private static var playing: Set<NSSound> = []

    private static func retainWhilePlaying(_ sound: NSSound) {
        playing.insert(sound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            playing.remove(sound)
        }
    }

    /// Base instances by name: we always play COPIES — the same named
    /// NSSound does not overlap with itself, and a quick repeat
    /// (changing the keep-awake duration) "sometimes" swallowed the sound.
    private static var bases: [String: NSSound] = [:]

    static func play(_ name: String, gain: Float = 1) {
        guard enabled else { return }
        let base = bases[name] ?? NSSound(named: name)
        guard let base else { return }
        bases[name] = base
        guard let sound = base.copy() as? NSSound else { return }
        sound.volume = 0.75 * gain
        retainWhilePlaying(sound)
        sound.play()
    }

    /// Ratchet tick on digit change — a short click for every step,
    /// like the iPhone picker wheel. A copy of the sound lets clicks overlap.
    static func scrubTick() {
        guard enabled else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTick) > 0.05 else { return }
        lastTick = now
        guard let sound = tickBase?.copy() as? NSSound else { return }
        sound.volume = 0.5
        retainWhilePlaying(sound)
        sound.play()
    }

    static func awakeCue(on: Bool) {
        play(on ? "Pop" : "Bottle", gain: 0.5)
    }

    static func alarm() {
        play("Glass")
    }

    /// A batch of files finished converting. Its own sound rather than the
    /// timer's: the alarm means "your time is up" and a converted folder does
    /// not (Anton, 2026-08-04). Loud enough to be heard over a browser.
    static func converted() {
        play("Ping", gain: 0.9)
    }
}
