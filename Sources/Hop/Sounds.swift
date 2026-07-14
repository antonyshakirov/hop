import AppKit

/// All app sounds behind a single switch. System notifications
/// live separately — the app does not control their sound.
@MainActor
enum Sounds {
    static let enabledKey = "appSoundsEnabled" // enabled by default
    static let alarmRepeatKey = "alarmRepeatSeconds"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var alarmRepeatSeconds: Int {
        UserDefaults.standard.object(forKey: alarmRepeatKey) as? Int ?? 120
    }

    private static var lastTick = Date.distantPast
    private static let tickBase = NSSound(named: "Pop")

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
        guard now.timeIntervalSince(lastTick) > 0.03 else { return }
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
}
