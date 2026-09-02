import AppKit
import HopCore
import SwiftUI

/// The one place that knows whether accessibility actually works, shared by the
/// keyboard lock, the window zones and the clipboard's paste.
/// SPEC: docs/spec.md — "A permission that goes missing says so".
@MainActor
final class AccessibilityWatch: ObservableObject {
    static let shared = AccessibilityWatch()

    private static let wasGrantedKey = "accessibilityWasGranted"

    @Published private(set) var alert: AccessibilityAlert = .none
    @Published private(set) var featureWasBlocked = false

    private var suppressionProven: Bool?
    private var noticeSent = false
    /// Runs only while something is wrong. Granting the permission in System
    /// Settings tells the app nothing, so a banner with no way of noticing the
    /// repair sits there over a working feature (Anton, 2026-09-02).
    private var poller: Timer?

    var showsBanner: Bool {
        AccessibilityVerdict.showsBanner(alert, featureWasBlocked: featureWasBlocked)
    }

    private init() {
        refresh()
    }

    func refresh() {
        guard !Snapshot.active else { return }
        let granted = AXIsProcessTrusted()
        let defaults = UserDefaults.standard
        if granted {
            defaults.set(true, forKey: Self.wasGrantedKey)
        } else {
            // Removing Hop from the list and adding it back — the fix for
            // `.stale` — passes through here, which is what retires the
            // measurement taken against the permission that is now gone.
            suppressionProven = nil
        }
        let fresh = AccessibilityVerdict.alert(
            granted: granted,
            wasGrantedBefore: defaults.bool(forKey: Self.wasGrantedKey),
            suppressionProven: suppressionProven)
        // Only on a real change: the agent bridge re-reads this every 5s and an
        // unchanged republish would redraw the panel on that beat.
        if fresh != alert { alert = fresh }
        // A permission that works again closes the case, notice included: the
        // next thing to fail deserves to be heard as news.
        if fresh == .none, featureWasBlocked {
            featureWasBlocked = false
            noticeSent = false
        }
        pollWhileBroken()
    }

    private func pollWhileBroken() {
        let wanted = alert != .none && featureWasBlocked
        guard wanted != (poller != nil) else { return }
        poller?.invalidate()
        poller = nil
        guard wanted else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    func noteSuppression(proven: Bool) {
        suppressionProven = proven
        refresh()
    }

    func reportBlocked(notify: Bool = true) {
        if !featureWasBlocked { featureWasBlocked = true }
        refresh()
        guard notify, !noticeSent, alert != .none else { return }
        noticeSent = true
        let lang = L10n.current
        Alerts.notice(title: L10n.t(titleKey, lang).capitalizedFirst,
                      body: L10n.t(bodyKey, lang).capitalizedFirst)
    }

    var bodyKey: L10nKey {
        switch alert {
        case .stale: return .permStaleBody
        case .lost: return .permLostBody
        default: return .permMissingBody
        }
    }

    var titleKey: L10nKey {
        alert == .stale ? .permStaleTitle : .permAccessibilityTitle
    }

    func openSettings() {
        guard let url = URL(string: KeyboardLockController.privacySettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Drop the row macOS is answering from and ask properly, which is the only
    /// move that reaches a switch already sitting in the position the user wants.
    func askAgain() {
        PermissionRepair.askAgain(.accessibility)
    }
}
