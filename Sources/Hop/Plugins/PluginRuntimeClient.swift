import Foundation
import Security
import Darwin
import HopPluginAPI
import HopPluginProcess

@MainActor
protocol PluginRuntimeTransport: AnyObject {
    var didStop: ((PluginError) -> Void)? { get set }
    func send(_ request: PluginRuntimeRequest) async throws -> PluginRuntimeReply
    func stop()
}

private final class PluginReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PluginRuntimeReply, Error>?
    init(_ continuation: CheckedContinuation<PluginRuntimeReply, Error>) { self.continuation = continuation }
    func resolve(_ result: Result<PluginRuntimeReply, Error>) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result)
    }
}

@MainActor
final class PluginRuntimeClient: PluginRuntimeTransport {
    var didStop: ((PluginError) -> Void)?
    private var watchToken: UUID?
    private var exitReason: PluginError?
    private var codeSentOnConnection = false
    private(set) var lastTransportError: [String: String]?
    private(set) var lastWaitStatus: Int?
    private(set) var sentRequests = 0
    private(set) var completedRequests = 0
    var processIdentifier: pid_t? { peer > 0 ? peer : nil }
    private var connection: NSXPCConnection?
    private var peer: pid_t = 0
    private var stopping: Task<Bool, Never>?
    private func connect() async throws -> NSXPCConnection {
        if let stopping {
            guard await stopping.value else { throw PluginError.runtimeStopped }
            self.stopping = nil
        }
        if let connection { return connection }
        guard let identifier = Bundle.main.bundleIdentifier, let team = Self.team(), identifier == "com.antonshakirov.minimo" || identifier == "com.antonshakirov.minimo.dev" else { throw PluginError.runtimeStopped }
        let name = identifier + ".plugin-runtime"
        let value = NSXPCConnection(serviceName: name)
        value.setCodeSigningRequirement("identifier \"\(name)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
        value.remoteObjectInterface = NSXPCInterface(with: PluginRuntimeXPC.self)
        let stopped: () -> Void = { [weak self, weak value] in
            Task { @MainActor in
                guard let self, let value, self.connection === value else { return }
                let reason: PluginError = self.codeSentOnConnection ? .runtimeStopped : .runtimeUnavailable
                self.connection = nil; self.peer = 0
                self.didStop?(reason)
            }
        }
        value.invalidationHandler = stopped
        value.interruptionHandler = stopped
        value.resume()
        connection = value
        let hello = PluginRuntimeRequest(operation: "hello", session: UUID(), generation: UUID(), request: UUID(), digest: "")
        do { _ = try await send(hello, over: value) }
        catch {
            value.invalidate()
            if connection === value { connection = nil }
            throw PluginError.runtimeUnavailable
        }
        peer = value.processIdentifier
        guard peer > 0, peer != getpid() else { value.invalidate(); connection = nil; throw PluginError.runtimeStopped }
        let descriptor = hop_plugin_watch_start(peer)
        guard descriptor >= 0 else { stop(); throw PluginError.runtimeStopped }
        let token = UUID()
        exitReason = nil
        codeSentOnConnection = false
        watchToken = token
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = hop_plugin_watch_exit(descriptor)
            let exitCode = status >= 0 && status & 127 == 0 ? (status >> 8) & 255 : -1
            let reason: PluginError = exitCode == 125 ? .memoryLimit : exitCode == 124 ? .deadlineExceeded : .runtimeStopped
            Task { @MainActor in
                guard let self, self.watchToken == token else { return }
                self.watchToken = nil; self.connection = nil; self.peer = 0
                self.exitReason = reason
                self.lastWaitStatus = status
                self.didStop?(reason)
            }
        }
        return value
    }
    func send(_ request: PluginRuntimeRequest) async throws -> PluginRuntimeReply {
        let connection: NSXPCConnection
        if request.operation == "unload" {
            guard let existing = self.connection else { throw PluginError.runtimeUnavailable }
            connection = existing
        } else {
            do { connection = try await connect() }
            catch { throw PluginError.runtimeUnavailable }
        }
        sentRequests += 1
        if request.operation != "unload" { codeSentOnConnection = true }
        do {
            let reply = try await send(request, over: connection)
            completedRequests += 1
            return reply
        }
        catch {
            if error as? PluginError == .runtimeStopped {
                for _ in 0..<10 where watchToken != nil { try? await Task.sleep(nanoseconds: 20_000_000) }
                throw exitReason ?? PluginError.runtimeStopped
            }
            throw error
        }
    }
    private func send(_ request: PluginRuntimeRequest, over connection: NSXPCConnection) async throws -> PluginRuntimeReply {
        let data = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let once = PluginReplyOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
                let value = error as NSError
                let metadata = ["domain": value.domain, "code": String(value.code),
                                "debug": value.userInfo[NSDebugDescriptionErrorKey] as? String ?? ""]
                Task { @MainActor in self?.lastTransportError = metadata }
                once.resolve(.failure(PluginError.runtimeStopped))
            } as? PluginRuntimeXPC
            guard let proxy else { once.resolve(.failure(PluginError.runtimeStopped)); return }
            proxy.request(data) { bytes in
                guard bytes.count <= 524_288 else { once.resolve(.failure(PluginError.runtimeStopped)); return }
                do { once.resolve(.success(try JSONDecoder().decode(PluginRuntimeReply.self, from: bytes))) }
                catch { once.resolve(.failure(PluginError.runtimeStopped)) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { once.resolve(.failure(PluginError.runtimeStopped)) }
        }
    }
    func stop() {
        guard let value = connection else { return }
        connection = nil
        watchToken = nil
        let oldPeer = peer
        peer = 0
        if oldPeer > 0, kill(oldPeer, 0) == -1, errno == ESRCH { value.invalidate(); stopping = nil; return }
        stopping = Task { [self] in
            let request = PluginRuntimeRequest(operation: "shutdown", session: UUID(), generation: UUID(), request: UUID(), digest: "")
            _ = try? await send(request, over: value)
            let observedPeer = oldPeer > 0 ? oldPeer : value.processIdentifier
            value.invalidate()
            guard observedPeer > 0 else { return false }
            let end = Date().addingTimeInterval(3)
            while Date() < end {
                if kill(observedPeer, 0) == -1 && errno == ESRCH { return true }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            return false
        }
    }
    private static func team() -> String? {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
