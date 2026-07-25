import AppKit
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
@MainActor
final class KeyboardLockController: ObservableObject {
    static let durationKey = "keyboardLockDuration"   // seconds
    static let durations: [Int] = [30, 60, 300]

    @Published private(set) var isLocked = false
    /// Seconds left before the automatic unlock; nil when the timer is off.
    @Published private(set) var remaining: Int?
    /// Accessibility has not been granted (macOS has just been asked).
    @Published private(set) var needsPermission = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var ticker: Timer?
    private var overlay: NSWindow?

    var duration: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Self.durationKey)
            return Self.durations.contains(stored) ? stored : 60
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.durationKey) }
    }

    /// Accessibility deep link, for when the user needs to grant it by hand.
    static let privacySettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    func toggle() {
        isLocked ? unlock() : lock()
    }

    func lock() {
        guard !isLocked, !Snapshot.active else { return }
        // Ask first: without the permission the tap silently never fires and the
        // cover would promise a lock that isn't there.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            needsPermission = true
            return
        }
        needsPermission = false
        guard installTap() else { return }
        isLocked = true
        remaining = duration
        showOverlay()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func unlock() {
        guard isLocked else { return }
        removeTap()
        ticker?.invalidate()
        ticker = nil
        remaining = nil
        isLocked = false
        hideOverlay()
    }

    private func tick() {
        guard let left = remaining else { return }
        if left <= 1 {
            unlock()
        } else {
            remaining = left - 1
        }
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
            return nil   // swallowed: the key does nothing at all
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            needsPermission = true
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
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
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = false
        window.contentView = NSHostingView(rootView: KeyboardLockOverlay(lock: self))
        window.setFrame(screen.frame, display: true)
        // The way out is a CLICK, so the cover must be able to take one: a
        // borderless window refuses to become key by default, and Hop is an
        // accessory app that is not frontmost. Without both of these the done
        // button could ignore the first click — with the keyboard locked, that
        // would leave the timer as the only escape.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        overlay = window
    }

    private func hideOverlay() {
        overlay?.orderOut(nil)
        overlay = nil
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
}
