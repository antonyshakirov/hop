import AppKit
import Combine
import HopCore
import IOKit.pwr_mgt
import HopHardwareKit

/// "Caffeine": keeps the Mac awake via a system power assertion.
/// Display assertions stay local; protected lid sessions use the hardware service.
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
    static let resumeKey = "awakeResumeAfterUpdate"
    private var relaunching = false
    private var updateLease: AwakeUpdateHandoff.Lease?
    private var inheritedHandoffID: UUID?

    @Published private(set) var isActive = false
    @Published private(set) var selected: Option?
    @Published private(set) var until: Date?
    @Published private(set) var heartbeat = Date()
    /// The figure the row currently shows, so a tick that would draw the same
    /// one publishes nothing (`AwakeCountdown`).
    private var shownMinutes: Int?

    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    /// Lid mode — visible to the UI: laptop icon in the module row.
    @Published private(set) var lidApplied = false
    @Published private(set) var lidChanging = false
    @Published private(set) var pendingLidTarget: Bool?
    @Published private(set) var lidFailure: HardwareReason?
    private var lidOperation = UUID()
    private var protectedLid: (Bool, Date?) async throws -> Bool = { on, until in
        try await CoolingController.shared.setLid(on, until: until)
        return CoolingController.shared.snapshot.lid
    }
    /// Blanks the built-in panel while the lid is closed in lid mode.
    private let lidDimmer = LidDisplayController()
    private var ticker: Timer?
    private var terminateObserver: NSObjectProtocol?

    /// Preview: the row shows the module ON, without holding a real power
    /// assertion or making a sound.
    /// SPEC: docs/spec.md — "Onboarding", the module preview.
    init(demo: Bool, protectedLid: ((Bool, Date?) async throws -> Bool)? = nil) {
        if let protectedLid { self.protectedLid = protectedLid }
        isActive = true
        selected = Self.options.first { $0.label == "4h" }
        until = Date().addingTimeInterval(4 * 3600)
    }

    init() {
        LidDimmer.restorePendingAtLaunch()
        let resume = Self.takeResume()
        let now = Date()
        let liveHandoff = resume?.handoffID.map { AwakeUpdateHandoff.isLive(id: $0) } ?? false
        let session = resume?.session(now: now, liveHandoff: liveHandoff) ?? .none
        inheritedHandoffID = liveHandoff ? resume?.handoffID : nil
        revertLidIfPending()
        switch session {
        case .endless:
            begin(Self.option(seconds: nil), until: nil, cue: false)
        case .until(let end):
            begin(Self.option(seconds: resume?.optionSeconds), until: end, cue: false)
        case .none:
            break
        }
        if !Snapshot.active, liveHandoff && session == .endless && !isActive {
            isActive = true
            selected = Self.option(seconds: nil)
            startTicker()
        } else if !Snapshot.active && (isActive || session == .none) {
            if let id = resume?.handoffID {
                if AwakeUpdateHandoff.finish(id: id) {
                    inheritedHandoffID = nil
                    UserDefaults.standard.removeObject(forKey: Self.resumeKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: Self.resumeKey)
            }
        }
        if lidApplied && !isActive {
            revertLidIfPending()
        }
        CoolingController.shared.lidDidStop = { [weak self] reason in
            guard let self else { return }
            self.lidApplied = false
            self.updateLidDimmer()
            if let reason, reason != .stopped, self.isActive { self.deactivate() }
        }
        // safety net: on app exit, release the assertion and restore lid sleep
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                guard let awake = AppModel.sharedKeepAwake else { return }
                if awake.relaunching {
                    awake.deactivate(silent: true)
                } else {
                    awake.deactivate()
                    awake.releaseLidForShutdown()
                }
            }
        }
    }

    var hasModuleWork: Bool { isActive || lidApplied || lidChanging }

    // SPEC: docs/spec.md — Protected lid sessions, the indicator follows the click.
    var lidShown: Bool { pendingLidTarget ?? lidApplied }

    // SPEC: disabling the whole module releases both independent controls.
    func stopForModuleOff() {
        deactivate()
        releaseLidForShutdown()
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
        begin(option, until: option.seconds.map { Date().addingTimeInterval($0) }, cue: true)
    }

    private func begin(_ option: Option, until end: Date?, cue: Bool) {
        guard createAssertion() else { return }

        isActive = true
        selected = option
        if cue { Sounds.awakeCue(on: true) }
        until = end
        shownMinutes = until.map { AwakeCountdown.minutes(remaining: $0.timeIntervalSinceNow) }

        startTicker()
    }

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func deactivate(silent: Bool = false) {
        if !relaunching && !cancelRelaunch(releaseActiveHandoff: true) { return }
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
        shownMinutes = nil
        ticker?.invalidate()
        ticker = nil
    }

    // SPEC: docs/spec.md — "Keep awake survives an update".
    func stashForRelaunch() throws {
        guard isActive || lidApplied else { return }
        guard !lidApplied, !lidChanging, !CoolingController.shared.blocksUpdates else { throw CocoaError(.userCancelled) }
        guard until == nil else { throw CocoaError(.userCancelled) }
        if inheritedHandoffID == nil {
            updateLease = try AwakeUpdateHandoff.start(
                keepDisplay: UserDefaults.standard.bool(forKey: Self.keepDisplayKey),
                willStart: { try self.saveResume(handoffID: $0) })
        }
        let id = updateLease?.id ?? inheritedHandoffID
        guard let id, AwakeUpdateHandoff.isLive(id: id) else {
            cancelRelaunch(); throw CocoaError(.executableNotLoadable)
        }
        do {
            try saveResume(handoffID: id)
            relaunching = true
        } catch {
            cancelRelaunch(); throw error
        }
    }

    private func saveResume(handoffID: UUID) throws {
        let record = AwakeResume(active: isActive, until: until, optionSeconds: selected?.seconds,
                                 lid: lidApplied, savedAt: Date(), handoffID: handoffID)
        let data = try JSONEncoder().encode(record)
        UserDefaults.standard.set(data, forKey: Self.resumeKey)
        guard UserDefaults.standard.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }

    func validateRelaunch() -> Bool {
        guard isActive || relaunching else { return true }
        guard until == nil, let id = updateLease?.id ?? inheritedHandoffID else { return false }
        return updateLease?.isReady ?? AwakeUpdateHandoff.isLive(id: id)
    }

    @discardableResult
    func cancelRelaunch(releaseActiveHandoff: Bool = false) -> Bool {
        relaunching = false
        if !releaseActiveHandoff && !hasAssertion && isActive { return true }
        if let id = updateLease?.id ?? inheritedHandoffID,
           !AwakeUpdateHandoff.finish(id: id) { return false }
        updateLease = nil
        inheritedHandoffID = nil
        UserDefaults.standard.removeObject(forKey: Self.resumeKey)
        return true
    }

    private static func takeResume() -> AwakeResume? {
        guard !Snapshot.active,
              let data = UserDefaults.standard.data(forKey: resumeKey) else { return nil }
        return try? JSONDecoder().decode(AwakeResume.self, from: data)
    }

    private static func option(seconds: TimeInterval?) -> Option {
        options.first { $0.seconds == seconds } ?? options[options.count - 1]
    }

    /// Ask immediately on exit; the service watchdog covers an interrupted exit.
    func releaseLidForShutdown() {
        if lidApplied || lidChanging {
            applyLidSleepDisabled(false, playCue: false)
        }
    }

    /// Apply a display assertion setting without changing the lid lease.
    func refreshForSettingsChange() {
        guard isActive else { return }
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
        }
        if createAssertion(), cancelRelaunch() {
            inheritedHandoffID = nil
        }
    }

    /// An explicit lid action may request installation or approval of the service.
    func toggleLid() {
        setLidEnabled(!(pendingLidTarget ?? lidApplied))
    }

    func setLidEnabled(_ on: Bool) {
        guard (pendingLidTarget ?? lidApplied) != on || lidFailure != nil else { return }
        applyLidSleepDisabled(on)
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

    // SPEC: docs/spec.md — Protected lid sessions.
    private func applyLidSleepDisabled(_ disabled: Bool, playCue: Bool = true) {
        let operation = UUID()
        lidOperation = operation
        lidChanging = true
        pendingLidTarget = disabled
        lidFailure = nil
        if playCue { Sounds.awakeCue(on: disabled) }
        Task { [weak self] in
            guard let self, self.lidOperation == operation else { return }
            defer {
                if self.lidOperation == operation {
                    self.lidChanging = false
                    self.pendingLidTarget = nil
                }
            }
            do {
                let applied = try await self.protectedLid(disabled, nil)
                guard self.lidOperation == operation else { return }
                self.lidApplied = applied
                self.updateLidDimmer()
            } catch {
                if self.lidOperation == operation {
                    self.lidFailure = error as? HardwareReason ?? .commandFailed
                }
            }
        }
    }

    /// SPEC: docs/spec.md — "Lid mode without a password", taking the rule back.
    static let lidRulePath = "/etc/sudoers.d/hop-pmset"

    static var lidRuleInstalled: Bool {
        if Snapshot.active { return CommandLine.arguments.contains("--revoke-row") }
        return FileManager.default.fileExists(atPath: lidRulePath)
    }

    /// Restores sleep first and drops the rule second, under ONE password prompt:
    /// removing the rule while `SleepDisabled` is 1 would leave a Mac that never
    /// sleeps and no longer any way for Hop to change that without asking again.
    func removeLidRule() {
        guard !Snapshot.active, Self.lidRuleInstalled, !lidApplied, !lidChanging,
              !CoolingController.shared.snapshot.lid else { return }
        let shell = "/usr/bin/pmset disablesleep 0 && /bin/rm -f \(Self.lidRulePath)"
        let source = "do shell script \"\(shell)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error == nil, !Self.lidRuleInstalled else { return }
        lidApplied = false
        UserDefaults.standard.set(false, forKey: "lidSleepAppliedPending")
        updateLidDimmer()
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

    // SPEC: docs/spec.md — Hardware service and legacy lid rules.
    private func sleepDisabledStateMatches(_ disabled: Bool) -> Bool {
        (try? SystemHardwareBackend().sleepDisabled()) == disabled
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

    /// Takes back a no-sleep state left standing by a crash or a kill: without
    /// this the Mac never sleeps again and Hop, restarted, does not know it.
    /// Only the silent path — an administrator dialog nobody asked for is not how
    /// an app opens, and the next lid toggle re-runs the whole flow anyway.
    /// SPEC: docs/spec.md — "Lid mode without a password".
    func revertLidIfPending() {
        guard !Snapshot.active,
              UserDefaults.standard.bool(forKey: "lidSleepAppliedPending"),
              !isActive
        else { return }
        guard runQuiet("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "0"]),
              sleepDisabledStateMatches(false)
        else { return }
        UserDefaults.standard.set(false, forKey: "lidSleepAppliedPending")
        lidApplied = false
        updateLidDimmer()
    }

    private func tick() {
        if isActive, !hasAssertion, let id = inheritedHandoffID {
            switch AwakeUpdateHandoff.recover(id: id, acquire: createAssertion) {
            case .owned:
                _ = cancelRelaunch()
            case .guarded:
                break
            case .lost:
                deactivate(silent: true)
                revertLidIfPending()
                return
            }
        }
        guard let until else { return }
        if until.timeIntervalSinceNow <= 0 {
            deactivate()
            return
        }
        let remaining = until.timeIntervalSinceNow
        guard AwakeCountdown.publishes(remaining: remaining, shown: shownMinutes) else { return }
        shownMinutes = AwakeCountdown.minutes(remaining: remaining)
        heartbeat = Date()
    }
}
