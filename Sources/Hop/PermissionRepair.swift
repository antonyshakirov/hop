import AppKit
import CoreGraphics

/// Asking macOS for a permission it believes it has already answered.
/// SPEC: docs/spec.md — "A permission that goes missing says so".
@MainActor
enum PermissionRepair {

    enum Service: String {
        case accessibility = "Accessibility"
        case screenCapture = "ScreenCapture"

        var isGranted: Bool {
            switch self {
            case .accessibility: return AXIsProcessTrusted()
            case .screenCapture: return CGPreflightScreenCaptureAccess()
            }
        }
    }

    private static var askedThisRun: Set<Service> = []

    /// Once per run per service; `force` is a button the user pressed, which may
    /// ask as often as it is pressed.
    static func askAgain(_ service: Service, force: Bool = false) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        guard force || !askedThisRun.contains(service) else { return }
        askedThisRun.insert(service)
        reset(service, bundleID: bundleID)
        // tccd needs a moment to write the reset before the request reads it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { request(service) }
    }

    /// SPEC: docs/spec.md — "A permission that goes missing says so", the 2.0 sweep.
    static func sweepDeadRowsOnce() {
        guard !Snapshot.active, let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: sweepKey) else { return }
        defaults.set(true, forKey: sweepKey)
        for service in [Service.accessibility, .screenCapture] where !service.isGranted {
            reset(service, bundleID: bundleID)
        }
    }

    /// Bumped by hand when a release must sweep again (a new signature).
    private static let sweepKey = "permissionsSwept.2.0"

    private static func reset(_ service: Service, bundleID: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", service.rawValue, bundleID]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private static func request(_ service: Service) {
        // WORKAROUND: Hop is an accessory app, so the dialog macOS raises for it
        // opens BEHIND whatever is in front and the press looks like it did
        // nothing (Anton, 2026-09-03). Activating first puts it where it was asked for.
        NSApp.activate(ignoringOtherApps: true)
        switch service {
        case .accessibility:
            let prompt = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(prompt)
        case .screenCapture:
            _ = CGRequestScreenCaptureAccess()
        }
    }
}
