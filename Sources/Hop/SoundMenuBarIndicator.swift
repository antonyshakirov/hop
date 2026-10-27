import Foundation

enum SoundMenuBarIndicator {
    static func isVisible(running: Bool, moduleActive: Bool,
                          defaults: UserDefaults = .standard) -> Bool {
        running && moduleActive
            && (defaults.object(forKey: SettingsKey.soundMenuBarMark) as? Bool ?? true)
    }
}
