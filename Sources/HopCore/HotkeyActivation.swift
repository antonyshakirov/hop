/// Which hotkey actions may hold their combination right now. A module that is
/// switched off claims nothing; the panel's own key is never withheld.
/// SPEC: docs/spec.md — "Which combination may be claimed".
public enum HotkeyActivation {
    public static func registrable(windowZones: Bool = true,
                                   inactiveModules: Set<String> = []) -> [ModuleAction] {
        var actions = [ModuleCatalog.panelAction]
        for module in ModuleCatalog.modules where !inactiveModules.contains(module.id) {
            actions.append(contentsOf: module.actions.filter { windowZones || !$0.isWindowZone })
        }
        return actions
    }
}
