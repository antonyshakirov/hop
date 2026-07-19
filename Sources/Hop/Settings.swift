import Foundation

enum SettingsKey {
    static let showMenuBarCountdown = "showMenuBarCountdown"
    /// Show the active tracker task's ticking "today" time in the menu bar; off by default.
    static let trackerTimeInBar = "trackerTimeInBar"
    static let alertMode = "alertMode"
    static let appLanguage = "appLanguage" // "auto" or an AppLanguage code
    /// Red "!" on the left of the icon when the monitor hits the red zone; off by default.
    static let menuBarRedAlert = "menuBarRedAlert"
    /// JSON-encoded PanelTabsModel: the user's spaces (icon tabs) and their module keys.
    static let panelTabs = "panelTabs"
    /// One-shot flag: models saved before the tracker had its own tab get the
    /// tracker lifted into a fresh "clock" tab exactly once. Set on the fresh
    /// migrate path too, so the seed never runs for new installs.
    static let trackerTabSeeded = "trackerTabSeeded"
    /// One-shot flag: models saved before the to-do module existed get "todos"
    /// placed directly after "tracker" exactly once. Set on the fresh migrate
    /// path too (migrate already pairs them), so the seed never runs for new
    /// installs.
    static let todosSeeded = "todosSeeded"
    /// One-shot flag: the legacy per-module `show*Module` toggles are read once
    /// and every OFF module is moved into the inactive bucket, after which
    /// visibility is pure membership and the toggles are never read again.
    static let moduleVisibilityMigrated = "moduleVisibilityMigrated"
}

/// Highlight thresholds for the system tab: at which value yellow and red kick in.
/// Battery semantics are inverted: below the threshold is worse.
enum Thresholds {
    static let tempYellowKey = "thTempYellow"
    static let tempRedKey = "thTempRed"
    static let loadYellowKey = "thLoadYellow"
    static let loadRedKey = "thLoadRed"
    static let diskYellowKey = "thDiskYellow"
    static let diskRedKey = "thDiskRed"
    static let battYellowKey = "thBattYellow"
    static let battRedKey = "thBattRed"

    static let tempYellowDefault = 70
    static let tempRedDefault = 90
    static let loadYellowDefault = 80
    static let loadRedDefault = 95
    // memory has no threshold: the row color follows macOS's own
    // memory-pressure signal (see SystemStats.memoryPressureLevel)
    static let diskYellowDefault = 85
    static let diskRedDefault = 95
    static let battYellowDefault = 30
    static let battRedDefault = 15

    static let allKeys = [
        tempYellowKey, tempRedKey, loadYellowKey, loadRedKey,
        diskYellowKey, diskRedKey, battYellowKey, battRedKey,
    ]

    static func resetAll() {
        for key in allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

enum AlertMode: String, CaseIterable, Identifiable {
    case soundAndBanner
    case soundOnly
    case silent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .soundAndBanner: return "sound + banner"
        case .soundOnly: return "sound only"
        case .silent: return "silent"
        }
    }

    var icon: String {
        switch self {
        case .soundAndBanner: return "bell.and.waves.left.and.right" // sound+banner: a bell with waves
        case .soundOnly: return "speaker.wave.2"
        case .silent: return "bell.slash"
        }
    }

    static var current: AlertMode {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.alertMode) ?? ""
        return AlertMode(rawValue: raw) ?? .soundAndBanner
    }
}
