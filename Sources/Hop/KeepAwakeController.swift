import AppKit
import Combine
import IOKit.pwr_mgt

/// "Caffeine": keeps the Mac awake via a system power assertion.
/// Optionally keeps the display on and (via pmset, with an admin password)
/// prevents the Mac from sleeping even with the lid closed.
@MainActor
final class KeepAwakeController: ObservableObject {
    struct Option: Equatable {
        let label: String
        let seconds: TimeInterval? // nil = forever
    }

    static let options: [Option] = [
        Option(label: "15", seconds: 15 * 60),
        Option(label: "30", seconds: 30 * 60),
        Option(label: "1h", seconds: 3600),
        Option(label: "2h", seconds: 2 * 3600),
        Option(label: "4h", seconds: 4 * 3600),
        Option(label: "8h", seconds: 8 * 3600),
        Option(label: "∞", seconds: nil),
    ]

    static let keepDisplayKey = "awakeKeepDisplay"
    static let lidKey = "awakeLidStay"

    @Published private(set) var isActive = false
    @Published private(set) var selected: Option?
    @Published private(set) var until: Date?
    @Published private(set) var heartbeat = Date()

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    /// Lid mode — visible to the UI: laptop icon in the module row.
    @Published private(set) var lidApplied = false
    /// Blanks the built-in panel while the lid is closed in lid mode.
    private let lidDimmer = LidDimmer()
    private var ticker: Timer?
    private var terminateObserver: NSObjectProtocol?

    init() {
        LidDimmer.restorePendingAtLaunch()
        // safety net: on app exit, release the assertion and restore lid sleep
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppModel.sharedKeepAwake?.deactivate()
                AppModel.sharedKeepAwake?.releaseLidForShutdown()
            }
        }
    }

    var remaining: TimeInterval? {
        until.map { max(0, $0.timeIntervalSinceNow) }
    }

    /// Tapping the active option turns it off; tapping any other switches to it.
    func toggle(_ option: Option) {
        if isActive && selected == option {
            deactivate()
        } else {
            activate(option)
        }
    }

    func activate(_ option: Option) {
        // silently drop the previous option — there must be exactly one activation
        // sound, the same for any switch, not an "off+on" pair
        deactivate(silent: true)

        guard createAssertion() else { return }

        isActive = true
        selected = option
        Sounds.awakeCue(on: true)
        until = option.seconds.map { Date().addingTimeInterval($0) }

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func deactivate(silent: Bool = false) {
        if isActive && !silent {
            Sounds.awakeCue(on: false)
        }
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
        }
        assertionID = 0
        isActive = false
        selected = nil
        until = nil
        ticker?.invalidate()
        ticker = nil
        // lid mode lives only inside an awake session: when the session ends
        // (manual off or time expiry, not an option switch), sleep comes back —
        // otherwise a closed lid would block sleep forever after the timer.
        if !silent && lidApplied {
            applyLidSleepDisabled(false, playCue: false) // the off cue already played
        }
    }

    /// Mandatory cleanup on exit: without it the Mac would be left
    /// with sleep disabled forever.
    func releaseLidForShutdown() {
        if lidApplied {
            applyLidSleepDisabled(false)
        }
    }

    /// Apply a settings change (assertion type / lid) on the fly.
    func refreshForSettingsChange() {
        guard isActive else { return }
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
        }
        _ = createAssertion()
    }

    /// Lid mode is enabled EXPLICITLY, via a button while keep-awake is active:
    /// the admin password is requested only at that moment.
    func toggleLid() {
        // the lid is an independent toggle; the moon and timers are unrelated
        let wasApplied = lidApplied
        applyLidSleepDisabled(!wasApplied)
        // play the sound only if the state actually changed (password not cancelled)
        if lidApplied != wasApplied {
            Sounds.awakeCue(on: lidApplied)
        }
    }

    private func createAssertion() -> Bool {
        // PreventUserIdleDisplaySleep keeps both the display and the system awake
        let keepDisplay = UserDefaults.standard.bool(forKey: Self.keepDisplayKey)
        let type = keepDisplay ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep"
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Hop — keep awake" as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        hasAssertion = true
        return true
    }

    /// pmset disablesleep requires root — we ask for the admin password.
    /// Turning awake off must restore sleep, otherwise the Mac stops sleeping at all.
    private func applyLidSleepDisabled(_ disabled: Bool, playCue: Bool = true) {
        let value = disabled ? "1" : "0"

        // path 1: no password — if the one-time sudoers setup is already in place.
        // Trust the exit status only when pmset's ACTUAL state confirms it: a stale
        // or half-broken setup must fall through to the password path below and
        // re-request rights, not silently claim success.
        if runQuiet("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", value]),
           sleepDisabledStateMatches(disabled) {
            lidApplied = disabled
            if playCue {
                Sounds.awakeCue(on: disabled) // lid clicks with the same cue as no-sleep
            }
            UserDefaults.standard.set(disabled, forKey: "lidSleepAppliedPending")
            updateLidDimmer()
            return
        }

        // path 2: first time — a single password prompt installs a sudoers rule
        // STRICTLY for the two commands pmset disablesleep 0/1 (validated by visudo)
        // and immediately applies the desired state. No password ever needed again.
        // the username is strictly validated: otherwise a hostile account could
        // inject a rule into sudoers
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return
        }
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0"
        // create the temp file in root-only /var/root via mktemp:
        // the unpredictable name closes the /tmp symlink attack
        let shell = "TMP=$(/usr/bin/mktemp /var/root/hop-pmset.XXXXXX) "
            + "&& printf '%s\\n' '\(rule)' > \"$TMP\" "
            + "&& /usr/sbin/visudo -cf \"$TMP\" "
            + "&& /usr/bin/install -m 0440 -o root -g wheel \"$TMP\" /etc/sudoers.d/hop-pmset "
            + "&& /bin/rm -f \"$TMP\" "
            + "&& /usr/bin/pmset disablesleep \(value)"
        // An AppleScript string literal is double-quoted, so every " and \ inside the
        // shell command must be escaped for AppleScript (backslashes FIRST, then
        // quotes) before it is embedded. Without this the `"$TMP"` in the command
        // closed the AppleScript string early: the script failed to compile, the admin
        // prompt never appeared, and the lid button silently did nothing.
        let escapedShell = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        do shell script "\(escapedShell)" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        // Claim success only when pmset's real state confirms the change — the
        // script's exit alone can lie (e.g. a partial failure after the prompt).
        if error == nil, sleepDisabledStateMatches(disabled) {
            lidApplied = disabled
            Sounds.awakeCue(on: disabled) // lid clicks with the same cue as no-sleep
            UserDefaults.standard.set(disabled, forKey: "lidSleepAppliedPending")
            updateLidDimmer()
        }
        // password cancelled or apply failed — leave the state as is (the icon stays
        // unlit, honest UI); the next click re-runs the whole flow, re-requesting
        // rights from scratch
    }

    /// The dimmer only runs while lid mode is active: the machine stays awake
    /// with the lid closed, so the built-in backlight must be blanked by us.
    private func updateLidDimmer() {
        if lidApplied {
            lidDimmer.start()
        } else {
            lidDimmer.stop()
        }
    }

    /// Ground truth for lid mode: does `pmset -g`'s SleepDisabled line match the
    /// requested state? Exit statuses of sudo/osascript alone can lie; the power
    /// manager's own report cannot. Unreadable output returns true (don't
    /// second-guess a state we cannot observe — behave exactly as before).
    private func sleepDisabledStateMatches(_ disabled: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return true }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8),
              let line = out.split(separator: "\n").first(where: { $0.contains("SleepDisabled") })
        else { return true }
        return line.contains(disabled ? "1" : "0")
    }

    /// Quiet launch without UI: true if the command succeeded (exit 0).
    private func runQuiet(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Undo a "stuck" no-sleep state (e.g. after a cancelled password or a crash).
    func revertLidIfPending() {
        if UserDefaults.standard.bool(forKey: "lidSleepAppliedPending"), !isActive {
            applyLidSleepDisabled(false)
        }
    }

    private func tick() {
        heartbeat = Date()
        if let until, until.timeIntervalSinceNow <= 0 {
            deactivate()
        }
    }
}
