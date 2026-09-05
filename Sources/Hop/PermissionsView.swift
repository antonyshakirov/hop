import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI
import UserNotifications

/// The "permissions" tab of the info window: every permission Hop can ask for,
/// what it is for, and whether it is granted right now — plus what Hop never
/// does. The list is taken from the CODE (the actual API calls), not written
/// from memory, and it stays that way: a new permission means a new row here.
struct PermissionsView: View {
    let lang: AppLanguage
    /// SPEC: docs/spec.md — "Lid mode without a password", taking the rule back.
    var removeLidRule: () -> Void = {}
    /// Onboarding shows the pledge on a screen of its own, one step earlier.
    var showsPledge = true

    /// Live state is read once per appearance; notifications answer asynchronously.
    @State private var notificationsGranted: Bool?
    /// SPEC: docs/spec.md — "Permissions (settings window)", the 2s re-read.
    @State private var poll = 0

    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: L10nKey
        let body: L10nKey
        /// nil — nothing to check (network, the admin prompt): informational only.
        let granted: Bool?
        /// System Settings deep link, when the user can flip it by hand.
        let settingsURL: String?
        /// nil where nothing can be asked for from here.
        var grant: (() -> Void)?
        /// Set where a permission already given can be taken back from here.
        var revoke: (() -> Void)?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                row(item)
            }
            restartRow
            Rectangle().fill(Theme.divider).frame(height: 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t(.permNeverTitle, lang))
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t(.permNeverBody, lang))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.docText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The closing statement, deliberately the loudest thing on the page:
            // a list of permissions reads as a list of risks unless somebody
            // says plainly what they are FOR and what is not happening. And it
            // ends with the receipt — the source is open (Anton, 2026-07-26).
            if showsPledge {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.t(.permPledgeTitle, lang))
                    .font(Theme.mono(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t(.permPledgeBody, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                    FooterLink(url: "https://github.com/antonyshakirov/hop",
                               label: L10n.t(.permPledgeLink, lang))
                        .font(Theme.mono(11, weight: .semibold))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .task {
            // UNUserNotificationCenter throws outright in a process with no
            // bundle (a snapshot render, a raw `swift run`), so it is only asked
            // in the real app.
            guard !Snapshot.active, Bundle.main.bundleIdentifier != nil else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsGranted = settings.authorizationStatus == .authorized
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            guard !Snapshot.active else { return }
            poll &+= 1
            guard Bundle.main.bundleIdentifier != nil else { return }
            Task {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                let granted = settings.authorizationStatus == .authorized
                await MainActor.run { notificationsGranted = granted }
            }
        }
    }

    private var items: [Item] {
        _ = poll
        return [
            Item(id: "network", symbol: "arrow.down.circle", title: .permNetworkTitle,
                 body: .permNetworkBody, granted: nil, settingsURL: nil),
            Item(id: "accessibility", symbol: "accessibility", title: .permAccessibilityTitle,
                 body: .permAccessibilityBody,
                 granted: Snapshot.active ? true : AXIsProcessTrusted(),
                 settingsURL: KeyboardLockController.privacySettingsURL,
                 grant: { PermissionRepair.askAgain(.accessibility, force: true) }),
            Item(id: "screen", symbol: "rectangle.dashed", title: .permScreenTitle,
                 body: .permScreenBody,
                 granted: Snapshot.active ? false : CGPreflightScreenCaptureAccess(),
                 settingsURL: ScreenTextController.privacySettingsURL,
                 grant: { PermissionRepair.askAgain(.screenCapture, force: true) }),
            Item(id: "notify", symbol: "bell", title: .permNotifyTitle, body: .permNotifyBody,
                 granted: Snapshot.active ? true : notificationsGranted,
                 settingsURL: "x-apple.systempreferences:com.apple.preference.notifications",
                 grant: { requestNotifications() }),
            Item(id: "admin", symbol: "lock", title: .permAdminTitle, body: .permAdminBody,
                 granted: nil, settingsURL: nil,
                 revoke: KeepAwakeController.lidRuleInstalled ? removeLidRule : nil),
            Item(id: "login", symbol: "power", title: .permLoginTitle, body: .permLoginBody,
                 granted: Snapshot.active ? true : SMAppService.mainApp.status == .enabled,
                 settingsURL: nil,
                 grant: { try? SMAppService.mainApp.register() }),
        ]
    }

    /// SPEC: docs/spec.md — "A permission that goes missing says so", the restart.
    @ViewBuilder
    private var restartRow: some View {
        if Snapshot.active ? CommandLine.arguments.contains("--restart-row")
                           : PermissionRepair.askedAnythingThisRun {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18, height: 24)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.t(.permRestartTitle, lang))
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 6)
                        Button { AppRelaunch.now(reopening: .permissions) } label: {
                            Text(L10n.t(.permRestart, lang))
                                .font(Theme.mono(10, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t(.permRestart, lang))
                        .hoverDim()
                    }
                    .frame(height: 24)
                    Text(L10n.t(.permRestartBody, lang))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.docText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A refusal already on file raises no dialog, so that case goes to the pane.
    private func requestNotifications() {
        guard !Snapshot.active, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                notificationsGranted = granted
                guard !granted,
                      let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
                else { return }
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The title line is a fixed 24pt tall — the height of the "grant access"
    /// button — and the icon is centred in the same 24, so a row with a button
    /// and a row without one hold their icon at the same place.
    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L10n.t(item.title, lang))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 6)
                    trailing(item)
                }
                .frame(height: 24)
                Text(L10n.t(item.body, lang))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.docText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// SPEC: docs/spec.md — "Permissions (settings window)", one trailing slot.
    @ViewBuilder
    private func trailing(_ item: Item) -> some View {
        if let revoke = item.revoke {
            Button(action: revoke) {
                Text(L10n.t(.permRevoke, lang))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.permRevoke, lang))
            .hoverDim()
        } else if item.granted == false, let grant = item.grant {
            Button(action: grant) {
                Text(L10n.t(.permGrant, lang))
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.chipBg, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.permGrant, lang))
            .hoverDim()
        } else {
            Text(statusText(item))
                .font(Theme.mono(9))
                .foregroundStyle(item.granted == true ? Theme.accentGreen : Theme.textTertiary)
                .lineLimit(1)
        }
    }

    private func statusText(_ item: Item) -> String {
        switch item.granted {
        case true: return L10n.t(.permGranted, lang)
        case false: return L10n.t(.permNotGranted, lang)
        case nil: return L10n.t(.permWhenUsed, lang)
        }
    }
}
