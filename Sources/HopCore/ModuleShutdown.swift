import Foundation

/// What switching a module off will interrupt, asked before it happens.
/// SPEC: docs/spec.md — "Switching a module off".
/// Tested by `ModuleShutdownTests`.
public enum ModuleShutdown {

    public enum Consequence: String, Sendable, Equatable, CaseIterable {
        case countdownStops
        case sleepAllowedAgain
        case openStretchFiled
        case downloadsPause
        case jobFinishesInItsWindow
        case remindersGoQuiet
    }

    /// What the modules are doing right now; the app fills it in from its
    /// controllers so the rule itself stays pure.
    public struct Activity: Equatable, Sendable {
        public var timerRunning: Bool
        public var keepAwakeActive: Bool
        public var trackerRunning: Bool
        public var activeDownloads: Int
        public var converterBusy: Bool
        public var archiveRunning: Bool
        public var armedReminders: Int

        public init(timerRunning: Bool = false,
                    keepAwakeActive: Bool = false,
                    trackerRunning: Bool = false,
                    activeDownloads: Int = 0,
                    converterBusy: Bool = false,
                    archiveRunning: Bool = false,
                    armedReminders: Int = 0) {
            self.timerRunning = timerRunning
            self.keepAwakeActive = keepAwakeActive
            self.trackerRunning = trackerRunning
            self.activeDownloads = activeDownloads
            self.converterBusy = converterBusy
            self.archiveRunning = archiveRunning
            self.armedReminders = armedReminders
        }
    }

    /// nil means "switch it off, there is nothing to say".
    public static func consequence(module: String, activity: Activity) -> Consequence? {
        switch module {
        case "timer": return activity.timerRunning ? .countdownStops : nil
        case "awake": return activity.keepAwakeActive ? .sleepAllowedAgain : nil
        case "tracker": return activity.trackerRunning ? .openStretchFiled : nil
        case "torrent": return activity.activeDownloads > 0 ? .downloadsPause : nil
        case "convert": return activity.converterBusy ? .jobFinishesInItsWindow : nil
        case "archive": return activity.archiveRunning ? .jobFinishesInItsWindow : nil
        case "todos": return activity.armedReminders > 0 ? .remindersGoQuiet : nil
        default: return nil
        }
    }

    public static func needsConfirmation(module: String, activity: Activity) -> Bool {
        consequence(module: module, activity: activity) != nil
    }
}
