import Foundation
import HopCore
import Darwin   // proc_listallpids / proc_pidpath / kill — orphan reaping

/// Runs the rqbit engine as a child process bound to loopback with a random
/// auth token, and waits until its HTTP API answers. Kept separate from the app
/// so its lifecycle (start when there are torrents, stop when idle) is explicit.
@MainActor
final class TorrentEngineProcess {
    private var process: Process?
    private(set) var baseURL: URL?
    private(set) var basicAuth: String?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Spawn rqbit and return the loopback base URL + "user:pass" token once the
    /// API is answering. Throws if it never comes up.
    @discardableResult
    func start(binary: URL, downloadFolder: URL, persistenceDir: URL,
               rateDownBps: Int?, rateUpBps: Int?) async throws -> (baseURL: URL, basicAuth: String) {
        stop()
        await Self.reapOrphanedEngines(binary: binary)
        let port = Self.freeLoopbackPort()
        let token = "hop:\(UUID().uuidString)"
        let process = Process()
        process.executableURL = binary
        process.arguments = RqbitLaunch.arguments(
            port: port, downloadFolder: downloadFolder.path, persistenceDir: persistenceDir.path,
            rateDownBps: rateDownBps, rateUpBps: rateUpBps
        )
        var env = ProcessInfo.processInfo.environment
        env["RQBIT_HTTP_BASIC_AUTH_USERPASS"] = token
        process.environment = env
        try process.run()
        self.process = process

        let base = URL(string: "http://127.0.0.1:\(port)")!
        self.baseURL = base
        self.basicAuth = token
        do {
            try await waitForHealth(base: base, auth: token)
        } catch {
            stop() // never leave an orphaned engine holding the port
            throw error
        }
        return (base, token)
    }

    func stop() {
        process?.terminate()
        process = nil
        baseURL = nil
        basicAuth = nil
    }

    /// Kill any rqbit spawned from OUR engine binary that outlived a previous app
    /// instance. `Process` does not terminate its children when the parent dies,
    /// so a crash or an abrupt quit reparents rqbit to launchd; the orphan keeps
    /// holding rqbit's fixed DHT/peer UDP ports, and a fresh engine then fails to
    /// bind them ("Address already in use"), which surfaced as "couldn't read this
    /// torrent" on every add. We only reap right before starting our own engine —
    /// by then `stop()` has ended this instance's process, so any process still
    /// running from our binary path is by definition a stale orphan, safe to kill.
    static func reapOrphanedEngines(binary: URL) async {
        let target = binary.resolvingSymlinksInPath().path
        let mine = getpid()
        let orphans = runningPids().filter { pid in
            pid > 0 && pid != mine && executablePath(of: pid) == target
        }
        guard !orphans.isEmpty else { return }
        for pid in orphans { kill(pid, SIGTERM) }
        // Wait (≤2s) for them to exit and release the ports before we bind, since
        // rqbit binds its DHT/peer ports once at startup and dies if they are taken.
        for _ in 0..<20 {
            if orphans.allSatisfy({ kill($0, 0) != 0 }) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        for pid in orphans where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// Every process ID via `sysctl(KERN_PROC_ALL)`. NOT `proc_listallpids`:
    /// on macOS 14 that silently returned ~150 of 600+ PIDs, so an orphaned
    /// engine usually wasn't in the list and never got reaped. sysctl returns
    /// the whole process table reliably.
    private static func runningPids() -> [pid_t] {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride).map { $0.kp_proc.p_pid }
    }

    /// The executable path of a PID, or nil if it can't be read. proc_pidpath
    /// itself is reliable (it was only the enumerator above that was broken).
    private static func executablePath(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    /// Poll GET /torrents until it answers 200 (≈5 s budget).
    private func waitForHealth(base: URL, auth: String) async throws {
        let url = base.appendingPathComponent("torrents")
        let header = "Basic \(Data(auth.utf8).base64EncodedString())"
        for _ in 0..<50 {
            var req = URLRequest(url: url)
            req.setValue(header, forHTTPHeaderField: "Authorization")
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        throw URLError(.cannotConnectToHost)
    }

    /// Ask the OS for a free loopback TCP port by binding to :0 and reading it back.
    static func freeLoopbackPort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 0 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 0 }
        var name = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &name) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard got == 0 else { return 0 }
        return Int(UInt16(bigEndian: name.sin_port))
    }
}
