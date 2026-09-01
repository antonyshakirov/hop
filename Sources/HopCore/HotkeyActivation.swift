/// Which hotkey actions may hold their combination right now.
///
/// SPEC: hop-private/specs/2026-09-01-settings-window-design.md — a hidden module
/// gives its combination back to other applications unless the user says otherwise.
public enum HotkeyActivation {
    public static func registrable(hidden: Set<String>, hiddenKeepHotkeys: Bool) -> [ModuleAction] {
        var actions = [ModuleCatalog.panelAction]
        for module in ModuleCatalog.modules where hiddenKeepHotkeys || !hidden.contains(module.id) {
            actions.append(contentsOf: module.actions)
        }
        return actions
    }
}
