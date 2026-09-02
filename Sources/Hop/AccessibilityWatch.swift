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
    private var expiry: Timer?
    /// How long the line stays before it takes itself away.
    private static let noticeLife: TimeInterval = 6

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
    }

    func noteSuppression(proven: Bool) {
        suppressionProven = proven
        refresh()
    }

    /// Nothing is explained here. macOS is already asking with its own dialog,
    /// and a panel that lectures on top of that is one surface too many
    /// (Anton, 2026-09-02).
    func reportBlocked(notify: Bool = true) {
        if !featureWasBlocked { featureWasBlocked = true }
        refresh()
        startExpiry()
        guard notify, !noticeSent, alert != .none else { return }
        noticeSent = true
        let lang = L10n.current
        Alerts.notice(title: L10n.t(.permAccessibilityTitle, lang).capitalizedFirst,
                      body: L10n.t(.permNoAccess, lang).capitalizedFirst)
    }

    private func startExpiry() {
        expiry?.invalidate()
        let timer = Timer(timeInterval: Self.noticeLife, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.featureWasBlocked else { return }
                self.featureWasBlocked = false
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }
}
