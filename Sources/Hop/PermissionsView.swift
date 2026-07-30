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

    /// Live state is read once per appearance; notifications answer asynchronously.
    @State private var notificationsGranted: Bool?

    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: L10nKey
        let body: L10nKey
        /// nil — nothing to check (network, the admin prompt): informational only.
        let granted: Bool?
        /// System Settings deep link, when the user can flip it by hand.
        let settingsURL: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                row(item)
            }
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
        .task {
            // UNUserNotificationCenter throws outright in a process with no
            // bundle (a snapshot render, a raw `swift run`), so it is only asked
            // in the real app.
            guard !Snapshot.active, Bundle.main.bundleIdentifier != nil else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsGranted = settings.authorizationStatus == .authorized
        }
    }

    private var items: [Item] {
        [
            Item(id: "network", symbol: "arrow.down.circle", title: .permNetworkTitle,
                 body: .permNetworkBody, granted: nil, settingsURL: nil),
            Item(id: "torrent", symbol: "arrow.up.arrow.down", title: .permTorrentTitle,
                 body: .permTorrentBody, granted: nil, settingsURL: nil),
            Item(id: "speed", symbol: "speedometer", title: .permSpeedTitle,
                 body: .permSpeedBody, granted: nil, settingsURL: nil),
            Item(id: "accessibility", symbol: "accessibility", title: .permAccessibilityTitle,
                 body: .permAccessibilityBody,
                 granted: Snapshot.active ? true : AXIsProcessTrusted(),
                 settingsURL: KeyboardLockController.privacySettingsURL),
            Item(id: "screen", symbol: "rectangle.dashed", title: .permScreenTitle,
                 body: .permScreenBody,
                 granted: Snapshot.active ? false : CGPreflightScreenCaptureAccess(),
                 settingsURL: ScreenTextController.privacySettingsURL),
            Item(id: "notify", symbol: "bell", title: .permNotifyTitle, body: .permNotifyBody,
                 granted: Snapshot.active ? true : notificationsGranted,
                 settingsURL: "x-apple.systempreferences:com.apple.preference.notifications"),
            Item(id: "admin", symbol: "lock", title: .permAdminTitle, body: .permAdminBody,
                 granted: nil, settingsURL: nil),
            Item(id: "login", symbol: "power", title: .permLoginTitle, body: .permLoginBody,
                 granted: Snapshot.active ? true : SMAppService.mainApp.status == .enabled,
                 settingsURL: nil),
        ]
    }

    private func row(_ item: Item) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L10n.t(item.title, lang))
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 6)
                    Text(statusText(item))
                        .font(Theme.mono(9))
                        .foregroundStyle(statusColor(item))
                        .lineLimit(1)
                }
                Text(L10n.t(item.body, lang))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.docText)
                    .fixedSize(horizontal: false, vertical: true)
                // Only where the user can actually change something by hand:
                // a granted permission needs no invitation to go looking.
                if let url = item.settingsURL, item.granted == false {
                    Button {
                        if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                    } label: {
                        HoverLabel(text: L10n.t(.ocrOpenSettings, lang), size: 9,
                                   color: Theme.textSecondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t(.ocrOpenSettings, lang))
                }
            }
        }
    }

    /// "granted" / "not granted" for what can be checked; everything else says
    /// it is asked for only when the feature is used.
    private func statusText(_ item: Item) -> String {
        switch item.granted {
        case true: return L10n.t(.permGranted, lang)
        case false: return L10n.t(.permNotGranted, lang)
        case nil: return L10n.t(.permWhenUsed, lang)
        }
    }

    private func statusColor(_ item: Item) -> Color {
        switch item.granted {
        case true: return Theme.accentGreen
        case false: return Theme.textTertiary
        case nil: return Theme.textTertiary
        }
    }
}
