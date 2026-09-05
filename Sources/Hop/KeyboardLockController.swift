import AppKit
import HopCore
import SwiftUI

/// "Cleaning mode": every key stops doing anything, so the keyboard can be
/// wiped without the Mac reacting — no need to shut it down or lift the lid.
/// The way out is the MOUSE (a button on the cover) or the timer, because a
/// keyboard shortcut would be exactly the thing that is switched off.
///
/// The keys are swallowed by a `CGEventTap`, which needs Accessibility — the
/// same permission the window manager already asks for. Nothing is recorded:
/// events are dropped, never inspected. The power button and Touch ID stay
/// alive; macOS reserves those and it would be wrong to take them anyway.
///
/// The cover goes up only once the lock has been PROVEN, never on the strength
/// of a permission check.
/// SPEC: docs/spec.md — "Keyboard lock (cleaning mode)".
@MainActor
final class KeyboardLockController: ObservableObject {
    static let durationKey = "keyboardLockDuration"   // seconds
    /// Offered lengths, plus 0 — "until I say so" (Anton, 2026-07-25). A zero
    /// runs with no timer at all: only the cover's button, the module's own
    /// button or opening the panel lets the keys go.
    static let durations: [Int] = [60, 300, 900, 0]

    @Published private(set) var isLocked = false
    /// Seconds left before the automatic unlock; nil when the timer is off.
    @Published private(set) var remaining: Int?
    /// When esc + shift went down together, nil when they are not both held.
    /// The cover's bar reads its progress off THIS, never off an implicit
    /// animation. SPEC: docs/spec.md — "Keyboard lock (cleaning mode)".
    @Published private(set) var chordSince: Date?

    var chordHeld: Bool { chordSince != nil }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var ticker: Timer?
    /// The proof's second tap, downstream of the first.
    private var verifyTap: CFMachPort?
    private var verifySource: CFRunLoopSource?
    private var verifying = false
    private var probeSeenByTap = false
    private var probeSeenDownstream = false
    private var probeTimer: Timer?
    private var probeCompletion: ((Bool) -> Void)?
    private var reArmedLastTick = false
    /// Live state of the unlock chord and its countdown.
    private var escapeDown = false
    private var shiftDown = false
    private var chordTimer: Timer?
    /// When the pair went down; every later event re-checks the deadline against it.
    private var chordStart: Date?
    private var overlay: NSWindow?
    /// Whoever was frontmost when the cover went up. Locking has to activate Hop
    /// so the cover's button answers the first click; unlocking has to give that
    /// app its focus back, or the keys are free but the first thing typed lands
    /// nowhere and the unlock reads as half a second late (Anton, 2026-07-27).
    private var appBeforeLock: NSRunningApplication?

    var duration: Int {
        get {
            // 0 is a valid choice (endless), so a missing key is told apart from
            // a stored zero by the object, not by the integer
            guard let stored = UserDefaults.standard.object(forKey: Self.durationKey) as? Int,
                  Self.durations.contains(stored) else { return 60 }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.durationKey) }
    }

    /// Accessibility deep link, for when the user needs to grant it by hand.
    static let privacySettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    func toggle() {
        isLocked ? unlock() : lock()
    }

    /// The module locked and counting down, for the onboarding picture: the row
    /// of durations says what you can pick, not what the module does.
    /// Nothing is tapped and no cover goes up — only the two published values.
    /// SPEC: docs/spec.md — "Onboarding", the module preview.
    func loadDemo() {
        isLocked = true
        remaining = 272
    }

    /// Locking IS the choice of a duration (Anton, 2026-07-25): the module has no
    /// separate start button — tapping "5 min" locks for five minutes. The value
    /// is remembered so the hotkey has something to use.
    /// `then` is handed true only once the keyboard is measurably locked.
    func lock(seconds: Int? = nil, then: ((Bool) -> Void)? = nil) {
        if let seconds { duration = seconds }
        guard !isLocked, !verifying, !Snapshot.active else { then?(false); return }
        // Checked apart: the repair after a refusal drops Hop's TCC row, which
        // a working grant must not pay for.
        guard AXIsProcessTrusted() else {
            refuse(then, askSystem: true)
            return
        }
        guard installTap() else {
            refuse(then, askSystem: false)
            return
        }
        proveLock { [weak self] proven in
            guard let self else { return }
            AccessibilityWatch.shared.noteSuppression(proven: proven)
            guard proven else {
                self.removeTap()
                // Trusted and still not suppressing: that repair waits for the
                // button, never a guess against a working grant.
                self.refuse(then, askSystem: false)
                return
            }
            self.isLocked = true
            self.remaining = self.duration > 0 ? self.duration : nil
            self.showOverlay()
            self.startTicker()
            then?(true)
        }
    }

    /// Measure without locking anything: a `.stale` verdict would otherwise
    /// outlive the repair, which macOS reports no differently.
    func remeasure() {
        guard !isLocked, !verifying, !Snapshot.active,
              AXIsProcessTrusted(), installTap() else { return }
        proveLock { [weak self] proven in
            self?.removeTap()
            AccessibilityWatch.shared.noteSuppression(proven: proven)
        }
    }

    /// The measurement, with two retries: refusing a lock that would have worked
    /// is its own kind of lie, and a busy main thread can lose a probe.
    private func proveLock(attempts: Int = 3, _ done: @escaping (Bool) -> Void) {
        verifySuppression { [weak self] proven in
            guard let self, !proven, attempts > 1 else {
                done(proven)
                return
            }
            self.proveLock(attempts: attempts - 1, done)
        }
    }

    /// No lock happened, and macOS does the asking.
    private func refuse(_ then: ((Bool) -> Void)?, askSystem: Bool) {
        AccessibilityWatch.shared.reportBlocked()
        if askSystem { PermissionRepair.askAgain(.accessibility) }
        then?(false)
    }

    /// One second, under an endless lock too: half countdown, half watchdog.
    private func startTicker() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func unlock() {
        guard isLocked else { return }
        // ORDER MATTERS. The two things the user can perceive — the keys coming
        // back and the cover leaving — happen first, in that order, before any
        // bookkeeping. Anything published to SwiftUI before the cover is gone
        // buys a layout pass the user reads as lag (Anton, 2026-07-27).
        removeTap()
        hideOverlay()
        restoreFocusAfterLock()
        ticker?.invalidate()
        ticker = nil
        remaining = nil
        isLocked = false
        escapeDown = false
        shiftDown = false
        reArmedLastTick = false
        cancelChord()
        // a short cue: with the cover gone and the keys back, the sound is what
        // says "you can type again" without looking anywhere
        Sounds.awakeCue(on: false)
    }

    private func tick() {
        guard isLocked else { return }
        let live = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        switch TapWatchdog.step(tapEnabled: live, reArmedLastTick: reArmedLastTick) {
        case .fine:
            reArmedLastTick = false
        case .reArm:
            reArmedLastTick = true
            reenableTap()
        case .giveUp:
            surrender()
            return
        }
        guard let left = remaining else { return }
        if left <= 1 {
            unlock()
        } else {
            remaining = left - 1
        }
    }

    /// The tap will not stay on, and a cover over a live keyboard is worse
    /// than no lock at all.
    private func surrender() {
        unlock()
        let lang = L10n.current
        Alerts.notice(title: L10n.t(.keylockLabel, lang).capitalizedFirst,
                      body: L10n.t(.keylockBroken, lang).capitalizedFirst)
    }

    // MARK: - The tap

    /// Keyboard events are swallowed at the session level: key presses, key
    /// releases and modifier changes, plus the system-defined class that carries
    /// the brightness/volume/media row — those are not "keys" to macOS and would
    /// otherwise still fire while the keyboard is being wiped.
    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << 14)   // NX_SYSDEFINED — the media/brightness row
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            // A tap that takes too long is disabled by macOS; re-arm it rather
            // than leaving the keyboard half-locked.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let userInfo {
                    let controller = Unmanaged<KeyboardLockController>
                        .fromOpaque(userInfo).takeUnretainedValue()
                    MainActor.assumeIsolated { controller.reenableTap() }
                }
                return Unmanaged.passUnretained(event)
            }
            if let userInfo, type.rawValue == 14 {
                let controller = Unmanaged<KeyboardLockController>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated { controller.noteSystemDefined(event) }
                return nil
            }
            // ESC + SHIFT held together is the keyboard's own way out: if the
            // mouse is gone or the cover is unreachable, holding the pair for a
            // few seconds releases the keys. A CHORD rather than a lone key —
            // something resting on the keyboard can hold one key down for
            // minutes, and that must not undo a cleaning lock (Anton,
            // 2026-07-26). Both keys are still swallowed on the way through.
            if let userInfo, type == .keyDown || type == .keyUp || type == .flagsChanged {
                let controller = Unmanaged<KeyboardLockController>
                    .fromOpaque(userInfo).takeUnretainedValue()
                let shift = event.flags.contains(.maskShift)
                let isEscape = (type == .keyDown || type == .keyUp)
                    && event.getIntegerValueField(.keyboardEventKeycode) == 53   // kVK_Escape
                MainActor.assumeIsolated {
                    controller.noteChord(escape: isEscape ? type == .keyDown : nil,
                                         shift: shift)
                }
            }
            // A short press of the power key is swallowed like everything else;
            // the emergency LONG hold is handled in hardware and never reaches
            // a tap, so a Mac can always still be forced off (Anton, 2026-07-25).
            return nil   // swallowed: the key does nothing at all
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    // MARK: - Proving the lock

    /// A subtype nothing in macOS acts on, so the probe changes nothing either
    /// way. SPEC: docs/spec.md — "Keyboard lock (cleaning mode)".
    private static let probeSubtype: Int16 = 0x4870
    private static let probeDeadline: TimeInterval = 0.3
    private static let probeGrace: TimeInterval = 0.06

    /// Proven when the main tap saw the probe and the downstream tap did not.
    private func verifySuppression(_ done: @escaping (Bool) -> Void) {
        verifying = true
        probeSeenByTap = false
        probeSeenDownstream = false
        probeCompletion = done
        installVerifyTap()
        postProbe()
        scheduleProbeDecision(after: Self.probeDeadline)
    }

    private func noteSystemDefined(_ event: CGEvent) {
        guard verifying, !probeSeenByTap, isProbe(event) else { return }
        probeSeenByTap = true
        scheduleProbeDecision(after: Self.probeGrace)
    }

    private func noteProbeDownstream(_ event: CGEvent) {
        guard verifying, isProbe(event) else { return }
        probeSeenDownstream = true
    }

    private func isProbe(_ event: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined else { return false }
        return ns.subtype.rawValue == Self.probeSubtype
    }

    private func scheduleProbeDecision(after delay: TimeInterval) {
        probeTimer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishProbe() }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        probeTimer = timer
    }

    private func finishProbe() {
        guard verifying else { return }
        verifying = false
        probeTimer?.invalidate()
        probeTimer = nil
        removeVerifyTap()
        let done = probeCompletion
        probeCompletion = nil
        done?(probeSeenByTap && !probeSeenDownstream)
    }

    private func postProbe() {
        guard let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, subtype: Self.probeSubtype, data1: 0, data2: -1
        ) else { return }
        // Entered where the hardware enters, so it meets the taps in the same
        // order a real key does.
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    private func installVerifyTap() {
        guard verifyTap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo, type.rawValue == 14 {
                let controller = Unmanaged<KeyboardLockController>
                    .fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated { controller.noteProbeDownstream(event) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << 14),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        verifyTap = tap
        verifySource = source
    }

    private func removeVerifyTap() {
        if let verifyTap {
            CGEvent.tapEnable(tap: verifyTap, enable: false)
            CFMachPortInvalidate(verifyTap)
        }
        if let verifySource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), verifySource, .commonModes)
        }
        verifyTap = nil
        verifySource = nil
    }

    /// Esc + shift held together for `escapeHoldSeconds` unlocks. A real timer
    /// rather than counting auto-repeats: shift is a modifier and never repeats,
    /// so there would be nothing to count while the pair is held.
    static let escapeHoldSeconds: TimeInterval = 5

    /// `escape` is nil for events that say nothing about that key (a bare
    /// modifier change); `shift` comes with every event, so it is always fresh.
    private func noteChord(escape: Bool?, shift: Bool) {
        guard isLocked else { return }
        if let escape { escapeDown = escape }
        shiftDown = shift
        guard escapeDown, shiftDown else {
            cancelChord()
            return
        }
        // Already counting: every auto-repeat of esc is a chance to notice that
        // the deadline has passed. That is what removes the half-second of "the
        // bar is full but nothing happened" — a Timer on a run loop busy with
        // the cover's animation can fire late, and repeats arrive every ~33ms
        // (Anton, 2026-07-26).
        if let start = chordStart {
            if Date().timeIntervalSince(start) >= Self.escapeHoldSeconds {
                cancelChord()
                unlock()
            }
            return
        }
        chordStart = Date()
        chordSince = chordStart
        let timer = Timer(timeInterval: Self.escapeHoldSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isLocked, self.escapeDown, self.shiftDown else { return }
                self.cancelChord()
                self.unlock()
            }
        }
        timer.tolerance = 0        // the deadline is the promise the bar makes
        // .common: a modal loop elsewhere must not stall the way out
        RunLoop.main.add(timer, forMode: .common)
        chordTimer = timer
    }

    private func cancelChord() {
        chordTimer?.invalidate()
        chordTimer = nil
        chordStart = nil
        chordSince = nil
    }

    private func reenableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - The cover

    /// A full-screen cover so the state is unmistakable — a locked keyboard with
    /// no visible sign would read as a frozen Mac. It sits above everything
    /// (screen-saver level) and follows to whichever space is in front.
    private func showOverlay() {
        guard overlay == nil, let screen = NSScreen.main else { return }
        let window = KeyboardLockWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        // Above the Dock, below the menu bar, which keeps its locked-keyboard
        // mark. SPEC: docs/spec.md — "Keyboard lock (cleaning mode)".
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.contentView = NSHostingView(
            rootView: KeyboardLockOverlay(lock: self).hopLayoutDirection())
        window.setFrame(screen.frame, display: true)
        // The way out is a CLICK, so the cover must be able to take one: a
        // borderless window refuses to become key by default, and Hop is an
        // accessory app that is not frontmost. Without both of these the done
        // button could ignore the first click — with the keyboard locked, that
        // would leave the timer as the only escape.
        //
        // Remember who is losing focus BEFORE taking it, so unlocking can hand
        // it straight back instead of leaving the user typing into Hop.
        let previous = NSWorkspace.shared.frontmostApplication
        appBeforeLock = previous?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil : previous
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        overlay = window
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
    }

    /// Give focus back to whoever had it before the cover took it. Hop is an
    /// accessory app with nothing else on screen, so staying frontmost means the
    /// user's next keystrokes go to no window at all — the keyboard is free and
    /// still feels stuck.
    private func restoreFocusAfterLock() {
        defer { appBeforeLock = nil }
        guard let app = appBeforeLock, !app.isTerminated else {
            NSApp.hide(nil)
            return
        }
        app.activate()
    }
}

/// A borderless window that CAN become key — the cover's button is the way out
/// of a locked keyboard, so it has to answer the very first click.
private final class KeyboardLockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The cover itself: what is happening, how long it lasts, and the one way out.
private struct KeyboardLockOverlay: View {
    @ObservedObject var lock: KeyboardLockController

    private var lang: AppLanguage { L10n.current }

    var body: some View {
        ZStack {
            Theme.background.opacity(0.94)
            VStack(spacing: 18) {
                Image(systemName: "keyboard")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text(L10n.t(.keylockTitle, lang))
                    .font(Theme.mono(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t(.keylockBody, lang))
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                // the keyboard's own way out, set apart and heavier: it is the
                // line that matters when the mouse is not within reach
                // (Anton, 2026-07-26)
                Text(L10n.t(.keylockChord, lang))
                    .font(Theme.mono(13, weight: .semibold))
                    .foregroundStyle(lock.chordHeld ? Theme.editing : Theme.textPrimary)
                    .multilineTextAlignment(.center)
                // Fills over the five seconds while the pair is held, and snaps
                // back the moment either key goes up: without it a hold is five
                // seconds of wondering whether anything is happening (Anton,
                // 2026-07-26).
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.divider)
                        .frame(width: 180, height: 4)
                    if let since = lock.chordSince {
                        TimelineView(.animation) { timeline in
                            Capsule()
                                .fill(Theme.editing)
                                .frame(width: 180 * Self.progress(since, timeline.date), height: 4)
                        }
                    }
                }
                .opacity(lock.chordHeld ? 1 : 0.35)
                if let remaining = lock.remaining {
                    Text(timeText(remaining))
                        .font(Theme.mono(30, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                Button {
                    lock.unlock()
                } label: {
                    Text(L10n.t(.keylockDone, lang))
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 10)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .padding(.top, 6)
            }
            .padding(40)
        }
        .ignoresSafeArea()
    }

    private func timeText(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Full AT the deadline, never before it.
    private static func progress(_ since: Date, _ now: Date) -> Double {
        let span = KeyboardLockController.escapeHoldSeconds
        return min(max(now.timeIntervalSince(since) / span, 0), 1)
    }
}
