import Foundation
import ServiceManagement

/// SPEC: docs/spec.md — Settings, launch at login is read and changed off the main thread.
@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin(
        isEnabled: {
            guard Bundle.main.bundleIdentifier != nil else { return false }
            return SMAppService.mainApp.status == .enabled
        },
        apply: { on in
            guard Bundle.main.bundleIdentifier != nil else { return }
            let service = SMAppService.mainApp
            if on, service.status != .enabled { try service.register() }
            if !on, service.status == .enabled { try service.unregister() }
        })

    /// The last state read from the system; nil until the first read finishes.
    @Published private(set) var known: Bool?
    private let isEnabled: @Sendable () -> Bool
    private let apply: @Sendable (Bool) throws -> Void
    private let queue = DispatchQueue(label: "hop.launch-at-login")
    private var ticket: UInt64 = 0

    init(isEnabled: @escaping @Sendable () -> Bool, apply: @escaping @Sendable (Bool) throws -> Void) {
        self.isEnabled = isEnabled
        self.apply = apply
    }

    /// The system state, or nil when a newer request has superseded this one.
    @discardableResult
    func read() async -> Bool? {
        ticket &+= 1
        let mine = ticket
        let isEnabled = isEnabled
        let value = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: isEnabled()) }
        }
        guard mine == ticket else { return nil }
        known = value
        return value
    }

    /// Shows `on` at once, applies it off the main thread and returns the state
    /// the system ended up in, or nil when a newer request has superseded this one.
    @discardableResult
    func set(_ on: Bool) async -> Bool? {
        ticket &+= 1
        let mine = ticket
        known = on
        let isEnabled = isEnabled, apply = apply
        let value = await withCheckedContinuation { continuation in
            queue.async {
                try? apply(on)
                continuation.resume(returning: isEnabled())
            }
        }
        guard mine == ticket else { return nil }
        known = value
        return value
    }
}
