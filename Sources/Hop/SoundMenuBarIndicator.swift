import Foundation

enum SoundMenuBarIndicator {
    static func isVisible(running: Bool, customized: Bool, moduleActive: Bool,
                          defaults: UserDefaults = .standard) -> Bool {
        running && customized && moduleActive
            && (defaults.object(forKey: SettingsKey.soundMenuBarMark) as? Bool ?? true)
    }
}
