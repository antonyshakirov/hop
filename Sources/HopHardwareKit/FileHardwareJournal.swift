import Darwin
import Foundation

// SPEC: docs/spec.md — Protected lid sessions, durable recovery.
public final class FileHardwareJournal: HardwareJournal {
    private let path: String
    private let expectedUID: uid_t
    private var directory: Int32 = -1
    private var lockFile: Int32 = -1

    public convenience init() { self.init(path: "/var/db/com.antonshakirov.hop-hardware", expectedUID: 0) }
    init(path: String, expectedUID: uid_t) { self.path = path; self.expectedUID = expectedUID }
    deinit { release(); if directory >= 0 { close(directory) } }

    public func acquire() throws {
        guard geteuid() == expectedUID else { throw HardwareReason.unauthorized }
        if lockFile >= 0 { return }
        if directory < 0 {
            if mkdir(path, 0o700) != 0 && errno != EEXIST { throw HardwareReason.commandFailed }
            let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw HardwareReason.commandFailed }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0, metadata.st_uid == expectedUID,
                  metadata.st_mode & 0o777 == 0o700 else { close(descriptor); throw HardwareReason.unauthorized }
            directory = descriptor
        }
        let descriptor = openat(directory, "owner.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw HardwareReason.commandFailed }
        do { try validate(descriptor, maximum: nil) }
        catch { close(descriptor); throw error }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { close(descriptor); throw HardwareReason.busy }
        lockFile = descriptor
    }

    public func load() throws -> HardwareRecovery? {
        guard lockFile >= 0 else { throw HardwareReason.unauthorized }
        let descriptor = openat(directory, "recovery.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 && errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw HardwareReason.restoreFailed }
        defer { close(descriptor) }
        try validate(descriptor, maximum: 16384)
        let data = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readDataToEndOfFile()
        guard data.count <= 16384 else { throw HardwareReason.restoreFailed }
        let record = try JSONDecoder().decode(HardwareRecovery.self, from: data)
        guard record.valid else { throw HardwareReason.restoreFailed }
        return record
    }

    public func save(_ record: HardwareRecovery) throws {
        guard lockFile >= 0, record.valid else { throw HardwareReason.unauthorized }
        let data = try JSONEncoder().encode(record)
        guard data.count <= 16384 else { throw HardwareReason.invalid }
        let name = "recovery-\(UUID().uuidString).tmp"
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw HardwareReason.commandFailed }
        defer { close(descriptor); unlinkat(directory, name, 0) }
        try data.withUnsafeBytes { buffer in
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: written), buffer.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw HardwareReason.commandFailed }
                written += count
            }
        }
        guard fsync(descriptor) == 0, renameat(directory, name, directory, "recovery.json") == 0,
              fsync(directory) == 0 else { throw HardwareReason.commandFailed }
    }

    public func clear() throws {
        guard lockFile >= 0 else { throw HardwareReason.unauthorized }
        if unlinkat(directory, "recovery.json", 0) != 0 && errno != ENOENT { throw HardwareReason.restoreFailed }
        guard fsync(directory) == 0 else { throw HardwareReason.restoreFailed }
    }

    public func release() {
        if lockFile >= 0 { flock(lockFile, LOCK_UN); close(lockFile); lockFile = -1 }
    }

    private func validate(_ descriptor: Int32, maximum: Int?) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_uid == expectedUID,
              metadata.st_mode & S_IFMT == S_IFREG, metadata.st_mode & 0o777 == 0o600,
              metadata.st_nlink == 1, maximum.map({ metadata.st_size >= 0 && metadata.st_size <= $0 }) ?? true
        else { throw HardwareReason.unauthorized }
    }
}
