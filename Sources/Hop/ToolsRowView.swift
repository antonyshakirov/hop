import HopCore
import SwiftUI

/// The three window modules — converter, archives, uninstaller — as ONE row,
/// split in equal parts: an icon and a single word each.
///
/// They are the same shape of thing (a row that opens a window and takes files),
/// so on a crowded space they cost three lines for very little. One word rather
/// than the module's full name is deliberate: "file converter" and "uninstall
/// apps" side by side do not fit a 340pt row in any language, let alone in German
/// (Anton, 2026-07-30). The full names stay in settings and in the help.
struct ToolsRowView: View {
    let lang: AppLanguage
    /// Only the tools actually present on this space, in the panel's own order.
    let tools: [Tool]

    enum Tool: String {
        case convert, archive, uninstall

        var symbol: String {
            switch self {
            case .convert: return "doc.badge.gearshape"
            case .archive: return "archivebox"
            case .uninstall: return "trash"
            }
        }
        /// One word, so three of them fit one row.
        var short: L10nKey {
            switch self {
            case .convert: return .toolsShortConvert
            case .archive: return .toolsShortArchive
            case .uninstall: return .toolsShortUninstall
            }
        }
        /// The full name, kept for the tooltip: the row is short, the meaning is not.
        var full: L10nKey {
            switch self {
            case .convert: return .convertLabel
            case .archive: return .archiveLabel
            case .uninstall: return .uninstallLabel
            }
        }
    }

    var open: (Tool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tools, id: \.rawValue) { tool in
                Button { open(tool) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Text(L10n.t(tool.short, lang))
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 7))
                .hoverHighlight(7)
                .help(L10n.t(tool.full, lang))
            }
        }
    }
}
