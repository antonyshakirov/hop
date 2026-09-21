import AppKit
import OSLog

/// SPEC: docs/spec.md — "Update channel", one Hop at a time.
@MainActor
enum SoleInstance {
    private static let log = Logger(subsystem: "com.antonshakirov.hop", category: "Launch")
    private static let graceSeconds: TimeInterval = 2

    static func claim() {
        guard !Snapshot.active, let id = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != mine && !$0.isTerminated }
        guard !others.isEmpty else { return }

        log.notice("\(others.count, privacy: .public) other copy(ies) of Hop running; asking them to quit")
        for app in others { app.terminate() }

        DispatchQueue.main.asyncAfter(deadline: .now() + graceSeconds) {
            for app in others where !app.isTerminated {
                log.error("a copy of Hop did not quit when asked; ending it")
                app.forceTerminate()
            }
        }
    }
}
