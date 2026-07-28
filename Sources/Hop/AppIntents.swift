import AppIntents
import Foundation
import HopCore

/// Spoken and Shortcuts-visible actions.
///
/// These are what let someone say "lock the keyboard in Hop for five minutes"
/// without building a Shortcut by hand first: App Intents publishes them to Siri,
/// Shortcuts and Spotlight straight from the app bundle. Every intent does its
/// work through the same `AgentCommand` vocabulary the command file and the
/// `hop://` links use, so there is ONE list of things Hop can be asked to do.
///
/// Apple's rule, not ours: an App Shortcut phrase MUST contain the application
/// name, so "lock the keyboard" alone will never reach Hop — Siri hands that to
/// the system. Every phrase below therefore names the app.
@available(macOS 14.0, *)
struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a timer"
    static var description = IntentDescription("Starts a countdown in Hop.")
    /// The panel does not have to open for this: the timer is a menu-bar thing.
    static var openAppWhenRun = false

    @Parameter(title: "Minutes", default: 10)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        AgentIntentRunner.run(.timerStart(seconds: max(1, minutes) * 60))
        return .result()
    }
}

@available(macOS 14.0, *)
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a task"
    static var description = IntentDescription("Adds a to-do to Hop.")
    static var openAppWhenRun = false

    @Parameter(title: "Task")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        AgentIntentRunner.run(.todoAdd(AgentCommand.TodoDraft(text: text)))
        return .result()
    }
}

@available(macOS 14.0, *)
struct LockKeyboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Lock the keyboard"
    static var description = IntentDescription("Locks the keyboard for cleaning.")
    static var openAppWhenRun = false

    @Parameter(title: "Minutes", default: 5)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        AgentIntentRunner.run(.keyboardLock(on: true, seconds: max(1, minutes) * 60))
        return .result()
    }
}

@available(macOS 14.0, *)
struct KeepAwakeIntent: AppIntent {
    static var title: LocalizedStringResource = "Keep the Mac awake"
    static var description = IntentDescription("Stops the Mac from going to sleep.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AgentIntentRunner.run(.keepAwake(on: true, seconds: nil))
        return .result()
    }
}

@available(macOS 14.0, *)
struct RecognizeTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Recognize text on screen"
    static var description = IntentDescription("Reads the text on the screen into the clipboard.")
    /// This one DOES bring the app forward: it puts a selection crosshair on the
    /// screen, and a crosshair from an app that is not there is a jump scare.
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AgentIntentRunner.run(.recognizeText)
        return .result()
    }
}

/// The spoken phrases. Localized through `AppShortcuts.strings` so Siri answers
/// in the user's own language; the app name is required in every one of them.
@available(macOS 14.0, *)
struct HopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTimerIntent(),
                    phrases: ["Start a timer in \(.applicationName)",
                              "Set a \(.applicationName) timer"],
                    shortTitle: "Start a timer",
                    systemImageName: "timer")
        AppShortcut(intent: AddTaskIntent(),
                    phrases: ["Add a task to \(.applicationName)",
                              "New task in \(.applicationName)"],
                    shortTitle: "Add a task",
                    systemImageName: "checklist")
        AppShortcut(intent: LockKeyboardIntent(),
                    phrases: ["Lock the keyboard in \(.applicationName)",
                              "\(.applicationName) keyboard lock"],
                    shortTitle: "Lock the keyboard",
                    systemImageName: "keyboard")
        AppShortcut(intent: KeepAwakeIntent(),
                    phrases: ["Keep the Mac awake with \(.applicationName)",
                              "\(.applicationName) keep awake"],
                    shortTitle: "Keep awake",
                    systemImageName: "moon.zzz")
        AppShortcut(intent: RecognizeTextIntent(),
                    phrases: ["Recognize text with \(.applicationName)",
                              "\(.applicationName) read the screen"],
                    shortTitle: "Recognize text",
                    systemImageName: "square.dashed")
    }
}

/// Bridges an intent to the running app. The intent process IS the app here
/// (macOS runs App Intents in-process for a running app), so the command goes
/// straight to the bridge; if the app is not running yet, the command file is
/// the fallback and gets picked up the moment it launches.
@MainActor
enum AgentIntentRunner {
    /// Set at launch by the app delegate.
    static weak var bridge: AgentBridge?

    static func run(_ command: AgentCommand) {
        if let bridge {
            bridge.perform(command)
        } else {
            AgentBridge.queueForNextLaunch(command)
        }
    }
}
