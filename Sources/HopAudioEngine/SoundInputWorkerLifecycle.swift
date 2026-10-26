import Foundation

/// Handles configuration notifications for one prepared worker output engine.
@MainActor
public final class SoundInputWorkerLifecycle {
    private var generation: UUID?

    public init() {}

    public func begin() -> UUID {
        let generation = UUID()
        self.generation = generation
        return generation
    }

    public func stop() { generation = nil }

    public func configurationChanged(generation: UUID, restart: () throws -> Void,
                                     silence: () -> Void, failed: () -> Void) {
        guard self.generation == generation else { return }
        do { try restart() }
        catch {
            self.generation = nil
            silence()
            failed()
        }
    }
}
