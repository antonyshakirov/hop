import Darwin
import Foundation

// SPEC: docs/spec.md — Protected lid sessions, bounded system commands.
enum HardwareCommand {
    static func run(_ executable: String, arguments: [String], timeout: TimeInterval = 3,
                    onSpawn: ((pid_t) -> Void)? = nil) throws -> String {
        guard executable.hasPrefix("/"), !executable.utf8.contains(0),
              arguments.allSatisfy({ !$0.utf8.contains(0) }), timeout.isFinite, timeout > 0, timeout <= 3
        else { throw HardwareReason.commandFailed }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        let descriptors = try makePipe()
        defer { close(descriptors.read) }
        var writerOpen = true
        defer { if writerOpen { close(descriptors.write) } }
        let flags = fcntl(descriptors.read, F_GETFL)
        guard flags >= 0, fcntl(descriptors.read, F_SETFL, flags | O_NONBLOCK) == 0
        else { throw HardwareReason.commandFailed }
        let pid = try spawn(executable, arguments: arguments, descriptors: descriptors)
        close(descriptors.write); writerOpen = false
        var reaped = false
        defer { if !reaped { terminateOwnedChild(pid) } }
        onSpawn?(pid)
        let data = try collect(pid, descriptor: descriptors.read, deadline: deadline, reaped: &reaped)
        guard let text = String(data: data, encoding: .utf8) else { throw HardwareReason.commandFailed }
        return text
    }

    private static func terminateOwnedChild(_ pid: pid_t) {
        var status: Int32 = 0
        var result: pid_t
        repeat { result = waitpid(pid, &status, WNOHANG) } while result < 0 && errno == EINTR
        guard result == 0 else { return }
        kill(pid, SIGKILL)
        while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
    }

    private static func makePipe() throws -> (read: Int32, write: Int32) {
        var original: [Int32] = [-1, -1]
        guard Darwin.pipe(&original) == 0 else { throw HardwareReason.commandFailed }
        let reader = fcntl(original[0], F_DUPFD_CLOEXEC, 3)
        let writer = fcntl(original[1], F_DUPFD_CLOEXEC, 3)
        close(original[0]); close(original[1])
        guard reader >= 3, writer >= 3 else {
            if reader >= 0 { close(reader) }
            if writer >= 0 { close(writer) }
            throw HardwareReason.commandFailed
        }
        return (reader, writer)
    }

    private static func spawn(_ executable: String, arguments: [String],
                              descriptors: (read: Int32, write: Int32)) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw HardwareReason.commandFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { throw HardwareReason.commandFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, descriptors.write, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors.read) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors.write) == 0
        else { throw HardwareReason.commandFailed }
        var argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { for pointer in argv { if let pointer { free(pointer) } } }
        guard argv.dropLast().allSatisfy({ $0 != nil }) else { throw HardwareReason.commandFailed }
        var pid: pid_t = 0
        guard posix_spawn(&pid, executable, &actions, &attributes, &argv, environ) == 0, pid > 0
        else { throw HardwareReason.commandFailed }
        return pid
    }

    private static func collect(_ pid: pid_t, descriptor: Int32, deadline: TimeInterval,
                                reaped: inout Bool) throws -> Data {
        var data = Data(), status: Int32 = 0
        while true {
            try drain(descriptor, into: &data, deadline: deadline)
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                reaped = true
                try drain(descriptor, into: &data, deadline: deadline)
                guard status == 0 else { throw HardwareReason.commandFailed }
                return data
            }
            if result < 0 {
                if errno == EINTR { continue }
                if errno == ECHILD { reaped = true }
                throw HardwareReason.commandFailed
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw HardwareReason.commandFailed }
            usleep(1_000)
        }
    }

    private static func drain(_ descriptor: Int32, into data: inout Data, deadline: TimeInterval) throws {
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw HardwareReason.commandFailed }
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= 16384 else { throw HardwareReason.commandFailed }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else if errno != EINTR {
                throw HardwareReason.commandFailed
            }
        }
    }
}
