import AppKit

/// Asking macOS for a permission it believes it has already answered.
/// SPEC: docs/spec.md — "A permission that goes missing says so".
@MainActor
enum PermissionRepair {

    enum Service: String {
        case accessibility = "Accessibility"
        case screenCapture = "ScreenCapture"
    }

    private static var askedThisRun: Set<Service> = []

    /// Once per run per service: a zone dragged five times must not raise five
    /// dialogs.
    static func askAgain(_ service: Service) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        guard !askedThisRun.contains(service) else { return }
        askedThisRun.insert(service)
        reset(service, bundleID: bundleID)
        // tccd needs a moment to write the reset before the request reads it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { request(service) }
    }

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
        switch service {
        case .accessibility:
            let prompt = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(prompt)
        case .screenCapture:
            _ = CGRequestScreenCaptureAccess()
        }
    }
}
