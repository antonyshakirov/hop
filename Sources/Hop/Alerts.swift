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

    /// UNUserNotificationCenter crashes outside an .app bundle (dev run via `swift run`),
    /// so checking bundleIdentifier is mandatory.
    private static var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static func requestPermissionIfPossible() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func postNotification(title: String? = nil, body: String? = nil) {
        guard notificationsAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.sound = .default // the banner plays its own sound — the app mute does not affect it
            let lang = L10n.current
            content.title = (title ?? L10n.t(.notifTitle, lang)).capitalizedFirst
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
