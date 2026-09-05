import Foundation
import HopCore

/// Whether a module is switched on, for the hotkeys, the menu bar and the
/// collectors. SPEC: docs/spec.md — "A module that is off is off everywhere".
@MainActor
enum ModuleActivation {
    static let didChange = Notification.Name("hop.moduleActivationDidChange")

    static func isOn(_ module: String) -> Bool {
        !inactiveModules().contains(module)
    }

    /// Cached against the stored text, not against `didChange`: the arrangement
    /// is written from a dozen places, and a cache that depends on every one of
    /// them to invalidate it would one day answer with yesterday's state.
    static func inactiveModules() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: SettingsKey.panelTabs) ?? ""
        if raw == cachedRaw { return cachedInactive }
        var value: Set<String> = []
        if var model = PanelTabsModel.decode(raw) {
            model.liftInactiveIntoHidden()
            value = model.hidden
        }
        cachedRaw = raw
        cachedInactive = value
        return value
    }

    static func announceChange() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static var cachedRaw: String?
    private static var cachedInactive: Set<String> = []
}
