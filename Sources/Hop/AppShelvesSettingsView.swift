import HopCore
import SwiftUI

/// The grids listed in settings: a name, how many icons it holds, its ✕, and the
/// switch for the names under the icons.
///
/// Its own view because it OBSERVES the shelves controller. Inside the settings
/// screen the same rows read `model.appShelves` without observing it, so a
/// toggled switch changed the stored value and the row kept drawing the old one —
/// the switch looked broken (Anton, 2026-07-30).
struct AppShelvesSettingsView: View {
    @ObservedObject var shelves: AppShelvesController
    let lang: AppLanguage
    var remove: (UUID) -> Void

    private func t(_ key: L10nKey) -> String { L10n.t(key, lang) }

    var body: some View {
        ForEach(shelves.shelves.shelves) { shelf in
            VStack(spacing: 8) {
                HStack {
                    Text(shelf.title.trimmingCharacters(in: .whitespaces).isEmpty
                         ? t(.appsLabel) : shelf.title)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(shelf.items.count)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Button { remove(shelf.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverDim()
                    .help(t(.appsRemoveShelf))
                }
                // Flush with the row above it: an indent here read as "belongs to
                // something else" (Anton, 2026-07-30).
                HStack {
                    Text(t(.appsShowNames))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Theme.MiniSwitch(isOn: Binding(
                        get: { shelves.shelves[shelf.id]?.showsLabels ?? true },
                        set: { shelves.setShowsLabels($0, for: shelf.id) }))
                }
            }
        }
    }
}
