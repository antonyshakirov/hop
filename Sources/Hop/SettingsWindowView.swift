import SwiftUI
import HopCore

/// Which page the settings window shows. The raw id is what `--settings-section`
/// takes and what the window is left on.
/// SPEC: hop-private/specs/2026-09-01-settings-window-design.md
enum SettingsSelection: Hashable {
    case general, spaces, hotkeys, permissions, updates, guide, about
    case module(String)

    var id: String {
        switch self {
        case .general: return "general"
        case .spaces: return "layout"
        case .hotkeys: return "hotkeys"
        case .permissions: return "permissions"
        case .updates: return "updates"
        case .guide: return "guide"
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
        case "guide": self = .guide
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

/// A group of settings drawn as one block: a filled, outlined card with its rows
/// inside. Groups are what a page is read by — a wall of rows on a flat window
/// has nothing to hold on to (Anton, 2026-09-01).
struct SettingsCard<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.rowBg))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider, lineWidth: 1))
    }
}

/// The hairline between two rows of a card: a page of switches is read line by
/// line, and a line needs an edge to be read along.
struct SettingsRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.vertical, -2)
    }
}

/// The caption above a card: what the group of settings is.
struct SettingsGroupLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.mono(9, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.leading, 2)
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
            Item(id: SettingsSelection.guide.id, icon: "book", title: t(.guideTab)),
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
                SettingsGroupLabel(title: t(.settingsTitle))
                    .padding(.leading, 10)
                    .padding(.bottom, 6)
                ForEach(sections) { row($0) }

                SettingsGroupLabel(title: t(.modulesLabel))
                    .padding(.leading, 10)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                ForEach(modules) { row($0) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.width)
        .background(Theme.rowBg)
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
                    // two lines rather than an ellipsis: the longest module
                    // names in de/fr do not fit 220pt on one
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Theme.chipBg : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Theme.controlStroke : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .hoverHighlight(6)
    }

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }
}
