import Foundation

/// Watches one file for changes made OUTSIDE the app — by an agent, a script, or
/// a folder syncing between machines — and calls back so the owner can reload.
///
/// Editors and JSON writers usually REPLACE a file rather than modify it in
/// place, which fires `.delete`/`.rename` and leaves the old descriptor pointing
/// at nothing; the watcher therefore re-arms itself on those events instead of
/// going quiet. A burst of events collapses into one callback.
@MainActor
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var pending: DispatchWorkItem?
    /// Long enough to swallow a write-then-rename, short enough to feel immediate.
    private static let coalesce: TimeInterval = 0.3

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
        if descriptor >= 0 { close(descriptor) }
    }

    /// Starts watching. A file that does not exist yet is not an error — the
    /// caller re-arms when it appears (the directory write shows up as a change
    /// to the file the moment something creates it).
    func start() {
        stop()
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            self.schedule()
            // The file we held is gone: whoever wrote it replaced it, so follow
            // the new one rather than watching a dead descriptor forever.
            if events.contains(.delete) || events.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesce) { [weak self] in
                    self?.start()
                }
            }
        }
        source.setCancelHandler { [descriptor] in
            if descriptor >= 0 { close(descriptor) }
        }
        self.source = source
        source.resume()
    }

    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesce, execute: work)
    }
}
