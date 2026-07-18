import Combine
import Foundation
import HopCore

/// Owns the on-disk tracker: loads `tracker.json` at launch, saves on every
/// engine mutation, and drives a 1 s ticker while a task is active so ticking
/// labels in the UI can redraw without polling.
@MainActor
final class TrackerController: ObservableObject {
    let engine: TrackerEngine
    /// Bumped once a second while a task is active — drives ticking labels.
    @Published private(set) var heartbeat: Date

    var isTracking: Bool { engine.activeTaskID != nil }

    /// Same Application Support/bundle-id folder the torrent module persists
    /// into; TrackerStore appends tracker.json itself.
    private let storeDir: URL
    private var ticker: Timer?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let id = Bundle.main.bundleIdentifier ?? "com.antonshakirov.minimo"
        storeDir = base.appendingPathComponent(id, isDirectory: true)

        let data = TrackerStore.load(from: storeDir)
        engine = TrackerEngine(data: data)
        heartbeat = Date()

        engine.onChange = { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: self.storeDir, withIntermediateDirectories: true)
            try? TrackerStore.save(self.engine.data, to: self.storeDir)
            self.reconcileTicker()
        }

        // a loaded open interval keeps ticking: the engine already counts
        // from its persisted start date, the ticker just drives the UI
        reconcileTicker()
    }

    private func reconcileTicker() {
        if isTracking {
            startTicker()
        } else {
            stopTicker()
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.heartbeat = Date()
            }
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
