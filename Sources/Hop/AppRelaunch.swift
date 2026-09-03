import AppKit

/// Quitting and coming straight back, so a permission granted a moment ago
/// reaches Hop at all.
/// SPEC: docs/spec.md — "A permission that goes missing says so", the restart.
@MainActor
enum AppRelaunch {
    private static let reopenKey = "reopenSettingsSection"

    static func now(reopening section: SettingsSelection?) {
        guard !Snapshot.active else { return }
        if let section {
            UserDefaults.standard.set(section.id, forKey: reopenKey)
        }
        // WORKAROUND: a plain `open` activates the instance still running and
        // nothing starts the new one after `terminate`, so a detached shell waits
        // for this process to die and opens the bundle afterwards.
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundle = Bundle.main.bundlePath
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(bundle)\""]
        try? relauncher.run()
        NSApp.terminate(nil)
    }

    /// The page a restart asked to come back to, taken once.
    static func pendingSettingsSection() -> String? {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey: reopenKey) else { return nil }
        defaults.removeObject(forKey: reopenKey)
        return id
    }
}
