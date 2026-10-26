import Foundation
import CryptoKit
import Darwin

public final class AgentOperationStore {
    public let requestsURL: URL
    private let root: Int32
    private let requests: Int32
    private let journal: Int32
    private let results: Int32
    private let limit: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private struct Record: Codable {
        let recordedAt: Date
        let result: AgentResultV2
    }

    public init(directory: URL, capacity: Int = 4096) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let root = try Self.directory(directory.path)
        var opened: [Int32] = []
        do {
            let fds = try ["agent-requests", "agent-journal", "agent-results"].map { name -> Int32 in
                if mkdirat(root, name, 0o700) != 0 && errno != EEXIST { throw AgentProtocolError("storage_unavailable") }
                let fd = try Self.directory(name, relativeTo: root)
                opened.append(fd)
                return fd
            }
            self.root = root; requests = fds[0]; journal = fds[1]; results = fds[2]
        } catch {
            opened.forEach { close($0) }; close(root); throw error
        }
        limit = capacity
        requestsURL = directory.appendingPathComponent("agent-requests", isDirectory: true)
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
    }
    deinit { [requests, journal, results, root].forEach { close($0) } }

    public func publishDiscoveryFile(_ data: Data, name: String) throws {
        guard ["agent-capabilities.json", "agent-state.json", "agent-commands.json"].contains(name) else { throw AgentProtocolError("invalid_discovery_path") }
        try replace(data, directory: root, name: name)
    }

    public func process(_ data: Data, expectedID: UUID? = nil, now: Date, perform: (AgentRequestV2) throws -> AgentResultV2) throws -> AgentResultV2 {
        guard data.count <= 65_536 else { throw AgentProtocolError("request_too_large") }
        let id = try (expectedID ?? AgentRequestV2.identifier(data)).uuidString.lowercased()
        let name = id + ".json", digest = requestDigest(data)
        if let record = try load(name) { return try replay(record.result, id: id, digest: digest) }
        try makeRoom(now: now)
        let parsed: AgentRequestV2
        do {
            parsed = try AgentRequestV2.parse(data, now: now)
            guard parsed.id.uuidString.lowercased() == id else { throw AgentProtocolError("request_filename_mismatch") }
        }
        catch {
            let code = (error as? AgentProtocolError)?.code ?? "invalid_request"
            let rejected = identified(.rejected(code), id: id, digest: digest)
            if try !claim(Record(recordedAt: now, result: rejected), name: name) {
                guard let record = try load(name) else { throw AgentProtocolError("storage_unavailable") }
                return try replay(record.result, id: id, digest: digest)
            }
            try publish(rejected, name: name)
            return rejected
        }
        let pending = identified(.indeterminate(), id: id, digest: digest)
        guard try claim(Record(recordedAt: now, result: pending), name: name) else {
            guard let existing = try load(name) else { throw AgentProtocolError("storage_unavailable") }
            return try replay(existing.result, id: id, digest: digest)
        }
        let outcome: AgentResultV2
        do { outcome = identified(try perform(parsed), id: id, digest: digest) }
        catch { try publish(pending, name: name); return pending }
        do { try replace(try encoder.encode(Record(recordedAt: now, result: outcome)), directory: journal, name: name) }
        catch { try publish(pending, name: name); return pending }
        try publish(outcome, name: name)
        return outcome
    }

    public func drain(now: Date, perform: (AgentRequestV2) throws -> AgentResultV2) throws {
        let names = try entries(requests).filter { $0.hasSuffix(".json") }.sorted().prefix(64)
        for name in names {
            let stem = String(name.dropLast(5))
            guard let id = UUID(uuidString: stem), stem == id.uuidString.lowercased() else { continue }
            let data: Data
            do {
                guard let bytes = try read(directory: requests, name: name, maximum: 65_536) else { continue }
                data = bytes
            } catch {
                let code = (error as? AgentProtocolError)?.code ?? "invalid_request"
                if let existing = try load(name) {
                    try publish(existing.result, name: name)
                } else {
                    try publish(identified(.rejected(code), id: stem, digest: ""), name: name)
                }
                _ = unlinkat(requests, name, 0)
                continue
            }
            do { _ = try process(data, expectedID: id, now: now, perform: perform) }
            catch {
                let code = (error as? AgentProtocolError)?.code ?? "storage_unavailable"
                let outcome = AgentResultV2(status: code == "journal_capacity_reached" ? "rejected" : "indeterminate", code: code)
                try publish(identified(outcome, id: stem, digest: requestDigest(data)), name: name)
            }
            if try read(directory: requests, name: name, maximum: 65_536) == data { _ = unlinkat(requests, name, 0) }
        }
    }

    private func requestDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func identified(_ value: AgentResultV2, id: String, digest: String) -> AgentResultV2 {
        var out = value; out.id = id; out.requestDigest = digest; return out
    }
    private func replay(_ original: AgentResultV2, id: String, digest: String) throws -> AgentResultV2 {
        let value = original.requestDigest == digest ? original : identified(.conflict(), id: id, digest: digest)
        try publish(value, name: id + ".json")
        return value
    }
    private func load(_ name: String) throws -> Record? {
        guard let data = try read(directory: journal, name: name, maximum: 8192), !data.isEmpty else { return nil }
        do { return try decoder.decode(Record.self, from: data) }
        catch { throw AgentProtocolError("journal_unreadable") }
    }
    private func makeRoom(now: Date) throws {
        var names = try entries(journal).filter { $0.hasSuffix(".json") }
        guard names.count >= limit else { return }
        for name in names {
            guard let record = try load(name), record.result.status != "indeterminate",
                  now.timeIntervalSince(record.recordedAt) > 30 * 86400 else { continue }
            _ = unlinkat(journal, name, 0); _ = unlinkat(results, name, 0)
        }
        names = try entries(journal).filter { $0.hasSuffix(".json") }
        guard names.count < limit else { throw AgentProtocolError("journal_capacity_reached") }
    }
    private func claim(_ record: Record, name: String) throws -> Bool {
        let fd = openat(journal, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if fd < 0 && errno == EEXIST { return false }
        guard fd >= 0 else { throw AgentProtocolError("storage_unavailable") }
        defer { close(fd) }
        try write(try encoder.encode(record), fd: fd)
        guard fsync(journal) == 0 else { throw AgentProtocolError("storage_unavailable") }
        return true
    }
    private func publish(_ result: AgentResultV2, name: String) throws {
        try replace(try encoder.encode(result), directory: results, name: name)
    }
    private func replace(_ data: Data, directory: Int32, name: String) throws {
        let temp = "." + UUID().uuidString
        let fd = openat(directory, temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AgentProtocolError("storage_unavailable") }
        defer { close(fd); _ = unlinkat(directory, temp, 0) }
        try write(data, fd: fd)
        guard renameat(directory, temp, directory, name) == 0, fsync(directory) == 0 else { throw AgentProtocolError("storage_unavailable") }
    }
    private func write(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentProtocolError("storage_unavailable") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw AgentProtocolError("storage_unavailable") }
    }
    private func read(directory: Int32, name: String, maximum: Int) throws -> Data? {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 && errno == ENOENT { return nil }
        guard fd >= 0 else { throw AgentProtocolError("unsafe_file") }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1, (info.st_mode & 0o077) == 0, info.st_size >= 0, info.st_size <= maximum else { throw AgentProtocolError("unsafe_file") }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while data.count <= maximum {
            let count = Darwin.read(fd, &buffer, min(buffer.count, maximum + 1 - data.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw AgentProtocolError("unsafe_file") }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
        throw AgentProtocolError("request_too_large")
    }
    private static func directory(_ path: String, relativeTo parent: Int32 = AT_FDCWD) throws -> Int32 {
        let fd = openat(parent, path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AgentProtocolError("unsafe_directory") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), fchmod(fd, 0o700) == 0 else {
            close(fd); throw AgentProtocolError("unsafe_directory")
        }
        return fd
    }
    private func entries(_ fd: Int32) throws -> [String] {
        let copy = dup(fd)
        guard copy >= 0 else { throw AgentProtocolError("storage_unavailable") }
        guard let directory = fdopendir(copy) else { close(copy); throw AgentProtocolError("storage_unavailable") }
        defer { closedir(directory) }
        rewinddir(directory)
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }
}
