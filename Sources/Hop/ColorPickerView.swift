import SwiftUI
import HopCore

/// Eyedropper module: one header line and the colors picked so far. Every color
/// carries all three notations at once and each is a button — clicking hex
/// copies hex, clicking rgb copies rgb (Anton, 2026-07-25). The old design hid
/// the result behind "it went to the clipboard", which nobody could see.
struct ColorPickerView: View {
    @ObservedObject var picker: ColorPickerController
    @ObservedObject var clipboard: ClipboardController
    let lang: AppLanguage
    /// The panel must get out of the way before the loupe appears — a popover
    /// swallows the first click and hides the pixel the user is aiming at.
    var closePanel: () -> Void = {}

    @AppStorage(ClipboardController.colorRowsKey) private var visibleRows =
        ClipboardController.defaultColorRows
    @State private var copiedKey: String?

    private var colors: [ClipboardItem] { clipboard.colors }

    /// The list is as tall as the user's chosen row count; everything older is
    /// reachable by scrolling, exactly like the clipboard shelf.
    private var listHeight: CGFloat {
        let rows = max(1, min(visibleRows, 10))
        return CGFloat(min(colors.count, rows)) * 30
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(L10n.t(.colorLabel, lang))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button {
                    closePanel()
                    picker.pick()
                } label: {
                    Text(L10n.t(picker.isSampling ? .colorPicking : .colorPick, lang))
                        .font(Theme.mono(10, weight: .bold))
                        .foregroundStyle(Theme.playFg)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Theme.playBg, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverDim()
                .disabled(picker.isSampling)
            }
            if colors.isEmpty {
                Text(L10n.t(.colorEmpty, lang))
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if Snapshot.active {
                // ImageRenderer can't draw a ScrollView — flat rows in a render
                VStack(spacing: 4) {
                    ForEach(colors.prefix(max(1, visibleRows))) { color in
                        colorRow(color)
                    }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(colors) { color in
                            colorRow(color)
                        }
                    }
                }
                .frame(height: listHeight)
            }
        }
    }

    /// One picked color: the swatch plus its three notations, each copyable.
    private func colorRow(_ item: ClipboardItem) -> some View {
        let parts = item.colorHex.flatMap(ColorFormatting.components(_:))
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(ColorSwatch.color(item.colorHex) ?? Theme.rowBg)
                .frame(width: 16, height: 16)
                // a white swatch would vanish on the light theme
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(Theme.controlStroke, lineWidth: 1))
            if let parts {
                ForEach(ColorFormat.allCases) { format in
                    valueButton(item: item, format: format, parts: parts)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Theme.rowBg, in: RoundedRectangle(cornerRadius: 5))
    }

    private func valueButton(
        item: ClipboardItem, format: ColorFormat, parts: (r: Int, g: Int, b: Int)
    ) -> some View {
        let text = ColorFormatting.string(format, r: parts.r, g: parts.g, b: parts.b)
        // rgb/hsl are long; the row drops the spaces so all three fit the panel
        let compact = text.replacingOccurrences(of: ", ", with: ",")
        let key = "\(item.id)-\(format.rawValue)"
        let isCopied = copiedKey == key
        return Button {
            picker.copy(text: text, hex: item.colorHex ?? "")
            copiedKey = key
            Task {
                try? await Task.sleep(for: .seconds(1))
                if copiedKey == key { copiedKey = nil }
            }
        } label: {
            Text(isCopied ? L10n.t(.ocrCopied, lang) : compact)
                .font(Theme.mono(9))
                .foregroundStyle(isCopied ? Theme.accentGreen : Theme.listText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(4)
    }
}

/// Hex string → SwiftUI color, shared by the module list and the clipboard row.
enum ColorSwatch {
    static func color(_ hex: String?) -> Color? {
        guard let hex, let parts = ColorFormatting.components(hex) else { return nil }
        return Color(red: Double(parts.r) / 255, green: Double(parts.g) / 255, blue: Double(parts.b) / 255)
    }
}
