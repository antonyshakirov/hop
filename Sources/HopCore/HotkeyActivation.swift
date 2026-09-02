/// Which hotkey actions may hold their combination right now.
///
/// SPEC: docs/spec.md — "Which combination may be claimed".
public enum HotkeyActivation {
    public static func registrable(windowZones: Bool = true) -> [ModuleAction] {
        var actions = [ModuleCatalog.panelAction]
        for module in ModuleCatalog.modules {
            actions.append(contentsOf: module.actions.filter { windowZones || !$0.isWindowZone })
        }
        return actions
    }
}
