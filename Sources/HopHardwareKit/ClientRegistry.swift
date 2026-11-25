import Foundation

public struct ClientProcess: Hashable, Sendable {
    public let pid: Int32
    public let started: UInt64
    public init(pid: Int32, started: UInt64) { self.pid = pid; self.started = started }
}

public struct ClientLease: Equatable, Sendable {
    public let owner: UUID
    let process: ClientProcess
    let connection: Int
}

// SPEC: docs/spec.md — Protected lid sessions, a dropped connection keeps the lease.
public final class ClientRegistry: @unchecked Sendable {
    private struct Entry { let owner: UUID; var connection: Int }
    private var entries: [ClientProcess: Entry] = [:]
    private var connections = 0
    private let lock = NSLock()
    private let alive: (ClientProcess) -> Bool

    public init(alive: @escaping (ClientProcess) -> Bool) { self.alive = alive }

    public func connect(_ process: ClientProcess) -> ClientLease {
        lock.withLock {
            connections += 1
            let owner = entries[process]?.owner ?? UUID()
            entries[process] = Entry(owner: owner, connection: connections)
            return ClientLease(owner: owner, process: process, connection: connections)
        }
    }

    public func isCurrent(_ lease: ClientLease) -> Bool {
        lock.withLock { lease.connection != 0 && entries[lease.process]?.connection == lease.connection }
    }

    public func retire(_ lease: ClientLease) {
        lock.withLock {
            if entries[lease.process]?.connection == lease.connection { entries[lease.process]?.connection = 0 }
        }
    }

    public func departed() -> [UUID] {
        lock.withLock {
            let gone = entries.filter { !alive($0.key) }
            for process in gone.keys { entries[process] = nil }
            return gone.values.map(\.owner)
        }
    }
}
