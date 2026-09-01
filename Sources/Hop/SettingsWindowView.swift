import SwiftUI
import HopCore

/// Which page the settings window shows. The raw id is what `--settings-section`
/// takes and what the window is left on.
/// SPEC: hop-private/specs/2026-09-01-settings-window-design.md
enum SettingsSelection: Hashable {
    case general, spaces, hotkeys, permissions, updates, about
    case module(String)

    var id: String {
        switch self {
        case .general: return "general"
        case .spaces: return "layout"
        case .hotkeys: return "hotkeys"
        case .permissions: return "permissions"
        case .updates: return "updates"
        case .about: return "about"
        case .module(let key): return "\(Self.modulePrefix)\(key)"
        }
    }

    static let modulePrefix = "module:"

    /// The ids the older chip switcher took keep working: "timer" and "monitor"
    /// were sections of their own and are now the pages of those two modules.
    init(id: String) {
        switch id {
        case "layout": self = .spaces
        case "hotkeys": self = .hotkeys
        case "permissions": self = .permissions
        case "updates": self = .updates
        case "about": self = .about
        case "modules": self = .spaces
        case "timer": self = .module("timer")
        case "monitor": self = .module("system")
        default:
            if id.hasPrefix(Self.modulePrefix) {
                self = .module(String(id.dropFirst(Self.modulePrefix.count)))
            } else {
                self = .general
            }
        }
    }
}

/// The settings window's left column: the sections, then every module of the
/// registry in panel order.
struct SettingsSidebar: View {
    let lang: AppLanguage
    @Binding var selection: String

    static let width: CGFloat = 220

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let title: String
    }

    private var sections: [Item] {
        [
            Item(id: SettingsSelection.general.id, icon: "gearshape", title: t(.aboutTabGeneral)),
            Item(id: SettingsSelection.spaces.id, icon: "square.grid.2x2", title: t(.settingsTabLayout)),
            Item(id: SettingsSelection.hotkeys.id, icon: "command", title: t(.hotkeysLabel)),
            Item(id: SettingsSelection.permissions.id, icon: "lock.shield", title: t(.permTab)),
            Item(id: SettingsSelection.updates.id, icon: "arrow.down.circle", title: t(.updatesLabel)),
            Item(id: SettingsSelection.about.id, icon: "info.circle", title: t(.aboutTitle)),
        ]
    }

    private var modules: [Item] {
        ModuleCatalog.modules.compactMap { entry in
            guard let key = ModulePresentation.titleKey(entry.id) else { return nil }
            return Item(
                id: SettingsSelection.module(entry.id).id,
                icon: ModulePresentation.icon(entry.id),
                title: L10n.t(key, lang)
            )
        }
    }

    var body: some View {
        SnapshotAwareScroll {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(sections) { row($0) }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.vertical, 10)

                ForEach(modules) { row($0) }
            }
            .padding(10)
        }
        .frame(width: Self.width)
    }

    private func row(_ item: Item) -> some View {
        let selected = selection == item.id
        return Button {
            selection = item.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(item.title)
                    .font(Theme.mono(11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Theme.fieldBg : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .hoverHighlight(6)
    }

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
}
