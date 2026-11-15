import AppKit
@preconcurrency import UserNotifications

@MainActor
enum Alerts {
    static func fire(mode: AlertMode, title: String? = nil, body: String? = nil) {
        switch mode {
        case .soundAndBanner:
            playSound()
            postNotification(title: title, body: body)
        case .soundOnly:
            playSound()
        case .silent:
            break
        }
    }

    private static func playSound() {
        Sounds.alarm()
    }

    /// XCTest can supply an identifier without an application bundle proxy.
    /// UserNotifications requires the actual .app, including for settings reads.
    private static var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestPermissionIfPossible() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A notification title as a system banner can carry it: one line, opening
    /// on the first letter the reader can see rather than on a fence.
    nonisolated static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces).capitalizedFirst
    }

    /// A banner that only informs: no sound, unlike the alarm's.
    static func notice(title: String, body: String) {
        postNotification(title: title, body: body, sound: false)
    }

    static func noticeIfAllowed(title: String, body: String) {
        guard notificationsAvailable, !Snapshot.active else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = oneLine(title)
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private static func postNotification(title: String? = nil, body: String? = nil,
                                         sound: Bool = true) {
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            // the banner plays its own sound — the app mute does not affect it
            content.sound = sound ? .default : nil
            let lang = L10n.current
            content.title = oneLine(title ?? L10n.t(.notifTitle, lang))
            content.body = body ?? L10n.t(.notifBody, lang)
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
