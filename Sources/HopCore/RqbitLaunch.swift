import Foundation

/// Builds rqbit's command-line arguments. Flag order is load-bearing (verified
/// on rqbit v8.1.1): global flags come BEFORE the `server start` subcommand, and
/// `--persistence-location` comes AFTER it. Rate limits are bytes/sec, included
/// only when set.
public enum RqbitLaunch {
    public static func arguments(port: Int, downloadFolder: String, persistenceDir: String,
                                 rateDownBps: Int?, rateUpBps: Int?) -> [String] {
        var args = ["--http-api-listen-addr", "127.0.0.1:\(port)"]
        if let rateDownBps { args += ["--ratelimit-download", String(rateDownBps)] }
        if let rateUpBps { args += ["--ratelimit-upload", String(rateUpBps)] }
        args += ["server", "start", "--persistence-location", persistenceDir, downloadFolder]
        return args
    }
}
