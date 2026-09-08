/// Which hotkey actions may hold their combination right now. A module that is
/// switched off claims nothing; the panel's own key is never withheld.
/// SPEC: docs/spec.md — "Which combination may be claimed".
public enum HotkeyActivation {
    public static func registrable(windowZones: Bool = true,
                                   inactiveModules: Set<String> = [],
                                   drawingLayerUp: Bool = false) -> [ModuleAction] {
        var actions = [ModuleCatalog.panelAction]
        for module in ModuleCatalog.modules where !inactiveModules.contains(module.id) {
            actions.append(contentsOf: module.actions.filter { action in
                guard windowZones || !action.isWindowZone else { return false }
                // The drawing layer's mode key answers to nothing while there is
                // no layer, so it holds its combination only while there is one.
                return drawingLayerUp || action != ModuleCatalog.annotatePassAction
            })
        }
        return actions
    }
}
