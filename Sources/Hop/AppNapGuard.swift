import Foundation

/// Keeps macOS from napping Hop while it owns work driven by its own timers.
/// With the lid closed and the display off, App Nap can hold a timer back for
/// minutes: the hardware service then misses the 20-second lease renewal and
/// ends the lid session after 90 seconds, and a timed Awake ends late.
/// The activity allows idle system sleep; preventing sleep stays the job of
/// the power assertion and the lid override.
// SPEC: docs/spec.md — Protected lid sessions, the background heartbeat.
final class AppNapGuard {
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var token: NSObjectProtocol?

    init(reason: String,
         begin: (() -> NSObjectProtocol)? = nil,
         end: ((NSObjectProtocol) -> Void)? = nil) {
        self.begin = begin ?? {
            ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: reason)
        }
        self.end = end ?? { ProcessInfo.processInfo.endActivity($0) }
    }

    var isHeld: Bool { token != nil }

    func hold(_ needed: Bool) {
        if needed, token == nil {
            token = begin()
        } else if !needed, let token {
            end(token)
            self.token = nil
        }
    }
}
