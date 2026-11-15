import Darwin
import Foundation
import HopHardwareKit

// SPEC: docs/spec.md — Hardware service updates, concurrent application copies.
final class AppProcessLock {
    private var descriptor: Int32 = -1

    static func acquire(_ name: String) throws -> AppProcessLock {
        guard let identifier = Bundle.main.bundleIdentifier, HardwareIdentity.applications.contains(identifier) else {
            throw HardwareReason.serviceMissing
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return try AppProcessLock(directory: base.appendingPathComponent(identifier)
            .appendingPathComponent("update-locks"), name: name)
    }

    init(directory: URL, name: String) throws {
        guard ["application", "hardware"].contains(name) else { throw HardwareReason.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let parent = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw HardwareReason.commandFailed }
        defer { close(parent) }
        var metadata = stat()
        guard fstat(parent, &metadata) == 0, metadata.st_uid == geteuid(), metadata.st_mode & 0o777 == 0o700
        else { throw HardwareReason.unauthorized }
        let file = openat(parent, name + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw HardwareReason.commandFailed }
        guard fstat(file, &metadata) == 0, metadata.st_uid == geteuid(), metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_mode & 0o777 == 0o600, metadata.st_nlink == 1 else {
            close(file); throw HardwareReason.unauthorized
        }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else { close(file); throw HardwareReason.busy }
        descriptor = file
    }

    func release() {
        if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 }
    }
    deinit { release() }
}
