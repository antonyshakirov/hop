import Foundation

struct SoundListeningMasterSnapshot: Equatable, Sendable {
    let uid: String?
    let attenuation: Double
    let muted: Bool

    init(uid: String?, scalar: Double?, muted: Bool?, decibels: Double? = nil, maximumDB: Double? = nil) {
        self.uid = uid; self.muted = muted == true
        if scalar == 0 { attenuation = 0 }
        else if let decibels, let maximumDB, decibels.isFinite, maximumDB.isFinite {
            attenuation = min(1, pow(10, min(0, decibels - maximumDB) / 20))
        } else if let scalar, scalar.isFinite { attenuation = min(1, max(0, scalar)) }
        else { attenuation = 1 }
    }
}

@MainActor
protocol SoundListeningMasterSource: AnyObject {
    func snapshot() -> SoundListeningMasterSnapshot
    func start(_ changed: @escaping () -> Void)
    func stop()
}

@MainActor
final class SoundListeningMasterObserver: SoundListeningMasterSource {
    private let read: () -> SoundListeningMasterSnapshot
    private let watch: (@escaping () -> Void) -> Void
    private let unwatch: () -> Void
    private var running = false

    init(read: @escaping () -> SoundListeningMasterSnapshot,
         watch: @escaping (@escaping () -> Void) -> Void = { _ in },
         unwatch: @escaping () -> Void = {}) {
        self.read = read; self.watch = watch; self.unwatch = unwatch
    }
    func snapshot() -> SoundListeningMasterSnapshot { read() }
    func start(_ changed: @escaping () -> Void) {
        guard !running else { return }
        running = true; watch(changed)
    }
    func stop() {
        guard running else { return }
        running = false; unwatch()
    }
}
