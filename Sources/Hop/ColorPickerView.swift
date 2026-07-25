import SwiftUI
import HopCore

/// Eyedropper module: the notation chips, the pick button, and the colors
/// picked recently. The history itself is the clipboard's — a picked color is a
/// clipboard entry like any other, so it is searchable and pasteable there. The
/// strip here is the same entries filtered to colors, kept to one row.
struct ColorPickerView: View {
    @ObservedObject var picker: ColorPickerController
    @ObservedObject var clipboard: ClipboardController
    let lang: AppLanguage
    /// The panel must get out of the way before the loupe appears — a popover
    /// swallows the first click and hides the pixel the user is aiming at.
    var closePanel: () -> Void = {}

    @AppStorage(ColorPickerController.formatKey) private var formatRaw = ColorFormat.hex.rawValue

    private var format: ColorFormat { ColorFormat(rawValue: formatRaw) ?? .hex }

    /// Recent colors, newest first. Six fit the panel width beside the button
    /// without the row wrapping in any language.
    private var recent: [ClipboardItem] {
        Array(clipboard.items.filter { $0.colorHex != nil }.prefix(6))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(L10n.t(.colorLabel, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                ForEach(ColorFormat.allCases) { option in
                    formatChip(option)
                }
            }
            HStack(spacing: 8) {
                Button {
                    closePanel()
                    picker.pick()
                } label: {
                    Text(picker.isSampling ? L10n.t(.colorPicking, lang) : L10n.t(.colorPick, lang))
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(picker.isSampling)
                Spacer(minLength: 0)
                if recent.isEmpty {
                    Text(L10n.t(.colorEmpty, lang))
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                } else {
                    ForEach(recent) { item in
                        swatch(item)
                    }
                }
            }
        }
    }

    /// A notation chip. Switching it also rewrites the newest color entry, so the
    /// change is visible (and pastes right) instead of only applying to the next
    /// pick — the format is what the user came here to control.
    private func formatChip(_ option: ColorFormat) -> some View {
        let active = option == format
        return Button {
            formatRaw = option.rawValue
            picker.reformatLatest()
        } label: {
            Text(option.label)
                .font(Theme.mono(9))
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(active ? Theme.chipBg : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
    }

    /// One recent color. Clicking it puts that color back on the pasteboard in
    /// the CURRENT notation — the same "click a row to copy it" rule the
    /// clipboard shelf follows.
    private func swatch(_ item: ClipboardItem) -> some View {
        Button {
            if let hex = item.colorHex { picker.copy(hex: hex) }
        } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(ColorSwatch.color(item.colorHex) ?? Theme.rowBg)
                .frame(width: 18, height: 18)
                // a white swatch on the light theme would otherwise vanish
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.controlStroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverDim()
        .help(item.text)
    }
}

/// Hex string → SwiftUI color, shared by the module strip and the clipboard row.
enum ColorSwatch {
    static func color(_ hex: String?) -> Color? {
        guard let hex, let parts = ColorFormatting.components(hex) else { return nil }
        return Color(red: Double(parts.r) / 255, green: Double(parts.g) / 255, blue: Double(parts.b) / 255)
    }
}
