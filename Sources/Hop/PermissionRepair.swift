import AppKit
import CoreGraphics
import HopCore

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

    private static func settingsURL(_ service: Service) -> String {
        switch service {
        case .accessibility: return KeyboardLockController.privacySettingsURL
        case .screenCapture: return ScreenTextController.privacySettingsURL
        }
    }

    private static var askedThisRun: Set<Service> = []
    private static var droppedThisRun: Set<Service> = []

    /// Whether anything has been asked for since Hop started.
    static var askedAnythingThisRun: Bool { !askedThisRun.isEmpty }

    /// The settings window on its permissions page, wired by the app delegate.
    static var openPermissionsPage: (() -> Void)?

    /// A feature the missing permission stopped: once per run per service.
    static func askAgain(_ service: Service) {
        ask(service, .featureStopped)
    }

    /// A "grant access" button, which asks as often as it is pressed.
    static func askByHand(_ service: Service) {
        ask(service, .button)
    }

    /// SPEC: docs/spec.md — "Screen recording is asked for before a module that reads the screen opens".
    static func askForTheScreen() {
        ask(.screenCapture, .screenModule)
    }

    private static func ask(_ service: Service, _ trigger: PermissionAsk.Trigger) {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let plan = PermissionAsk.plan(trigger,
                                            askedThisRun: askedThisRun.contains(service),
                                            droppedThisRun: droppedThisRun.contains(service))
        else { return }
        askedThisRun.insert(service)
        if plan.dropsTheRow {
            droppedThisRun.insert(service)
            reset(service, bundleID: bundleID)
        }
        switch plan.opens {
        case .permissionsPage:
            openPermissionsPage?()
        case .systemSettings:
            if let url = URL(string: settingsURL(service)) { NSWorkspace.shared.open(url) }
        case nil:
            break
        }
        guard plan.requests else { return }
        // tccd needs a moment to write the reset before the request reads it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { request(service) }
    }

    /// SPEC: docs/spec.md — "A permission that goes missing says so", the 1.10.0 reset.
    static func resetEverythingOnce() {
        guard !Snapshot.active, let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: resetKey) else { return }
        defaults.set(true, forKey: resetKey)
        reset("All", bundleID: bundleID)
        droppedThisRun = [.accessibility, .screenCapture]
        AccessibilityWatch.forgetGrant()
    }

    /// Bumped by hand when a release must clear permissions again.
    private static let resetKey = "permissionsReset.1.10.0"

    private static func reset(_ service: Service, bundleID: String) {
        reset(service.rawValue, bundleID: bundleID)
    }

    private static func reset(_ service: String, bundleID: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", service, bundleID]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private static func request(_ service: Service) {
        // WORKAROUND: Hop is an accessory app, so the dialog macOS raises for
        // it opens BEHIND whatever is in front and the press looks like it did
        // nothing. Activating first puts it where it was asked for.
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
