import Foundation

/// Writes `tracker.json` on a serial queue so a click never waits for the disk.
/// Writes coalesce: only the newest snapshot is written, and it is always the last one.
/// SPEC: docs/spec.md — Time tracker, history saves happen off the main thread.
public final class TrackerWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "hop.tracker.write", qos: .utility)
    private let lock = NSLock()
    private var pending: TrackerData?
    private let directory: URL
    private let save: @Sendable (TrackerData, URL) throws -> Void
    private let failed: @Sendable (Error) -> Void

    public init(directory: URL,
                save: @escaping @Sendable (TrackerData, URL) throws -> Void = { try TrackerStore.save($0, to: $1) },
                failed: @escaping @Sendable (Error) -> Void = { _ in }) {
        self.directory = directory
        self.save = save
        self.failed = failed
    }

    public func write(_ data: TrackerData) {
        lock.lock(); pending = data; lock.unlock()
        queue.async { [self] in
            lock.lock(); let next = pending; pending = nil; lock.unlock()
            guard let next else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try save(next, directory)
            } catch { failed(error) }
        }
    }

    /// Returns once every write requested so far is on disk; called at quit.
    public func flush() { queue.sync {} }
}
