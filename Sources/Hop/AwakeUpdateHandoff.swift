import Darwin
import Foundation
import IOKit.pwr_mgt

// SPEC: docs/spec.md — "Updates during active work (2.4 development)".
enum AwakeUpdateHandoff {
    static let startupTimeout: TimeInterval = 2
    static let pollInterval: TimeInterval = 0.05
    static let releasePollInterval: TimeInterval = 1
    private static let flag = "--awake-update-guard"

    struct Lease {
        let id: UUID
        let process: Process
        func cancel() { AwakeUpdateHandoff.finish(id: id) }
        var isReady: Bool { process.isRunning && AwakeUpdateHandoff.isLive(id: id) }
    }

    static func directory(id: UUID) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hop-awake-handoff-\(id.uuidString)")
    }

    static func makeDirectory(id: UUID) throws -> URL {
        let url = directory(id: id)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    private static func validDirectory(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
            && (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
            && (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
    }

    static func start(keepDisplay: Bool, willStart: (UUID) throws -> Void) throws -> Lease {
        let id = UUID(), url = try makeDirectory(id: id)
        let process = Process()
        guard let executable = Bundle.main.executableURL else {
            finish(id: id); throw CocoaError(.executableNotLoadable)
        }
        process.executableURL = executable
        process.arguments = [flag, id.uuidString, keepDisplay ? "display" : "system"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try willStart(id)
            try process.run()
            let deadline = ProcessInfo.processInfo.systemUptime + startupTimeout
            let ready = url.appendingPathComponent("ready")
            while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                if FileManager.default.fileExists(atPath: ready.path), isLive(id: id) {
                    return Lease(id: id, process: process)
                }
                Thread.sleep(forTimeInterval: pollInterval)
            }
            throw CocoaError(.executableNotLoadable)
        } catch {
            finish(id: id)
            if process.isRunning { process.terminate() }
            throw error
        }
    }

    static func isLive(id: UUID) -> Bool {
        let url = directory(id: id)
        guard validDirectory(url), FileManager.default.fileExists(atPath: url.appendingPathComponent("ready").path) else { return false }
        let fd = open(url.appendingPathComponent("lock").path, O_RDWR | O_NOFOLLOW)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            flock(fd, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }

    static func processID(id: UUID) -> pid_t? {
        guard isLive(id: id),
              let data = try? Data(contentsOf: directory(id: id).appendingPathComponent("ready")),
              let text = String(data: data, encoding: .utf8), let pid = pid_t(text), pid > 0 else { return nil }
        return pid
    }

    @discardableResult
    static func finish(id: UUID) -> Bool {
        let url = directory(id: id)
        if !FileManager.default.fileExists(atPath: url.path) { return true }
        guard validDirectory(url) else { return false }
        do { try FileManager.default.removeItem(at: url); return true }
        catch { return false }
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains(flag) else { return }
        guard args.count == 4, args[1] == flag, let id = UUID(uuidString: args[2]),
              args[3] == "display" || args[3] == "system" else { exit(1) }
        serve(id: id, keepDisplay: args[3] == "display", acquire: acquireAssertion,
              sleep: Thread.sleep(forTimeInterval:))
        exit(0)
    }

    static func serve(id: UUID, keepDisplay: Bool,
                      acquire: (Bool) -> (() -> Void)?, sleep: (TimeInterval) -> Void) {
        let url = directory(id: id)
        guard validDirectory(url) else { return }
        let fd = open(url.appendingPathComponent("lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        defer { flock(fd, LOCK_UN); finish(id: id) }
        guard let release = acquire(keepDisplay) else { return }
        defer { release() }
        let ready = Data(String(ProcessInfo.processInfo.processIdentifier).utf8)
        guard (try? ready.write(to: url.appendingPathComponent("ready"), options: .atomic)) != nil else { return }
        while validDirectory(url) { sleep(releasePollInterval) }
    }

    enum Recovery: Equatable { case owned, guarded, lost }

    static func recover(id: UUID, acquire: () -> Bool) -> Recovery {
        if acquire() { return .owned }
        return isLive(id: id) ? .guarded : .lost
    }

    private static func acquireAssertion(keepDisplay: Bool) -> (() -> Void)? {
        let type = keepDisplay ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep"
        var id: IOPMAssertionID = 0
        guard IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Hop — update handoff" as CFString, &id) == kIOReturnSuccess else { return nil }
        return { IOPMAssertionRelease(id) }
    }
}
