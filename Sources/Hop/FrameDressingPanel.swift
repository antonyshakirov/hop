import AppKit
import HopCore
import SwiftUI

/// The background the frame stands on and the air around it, in a popover hung
/// off the toolbar. Off by default, so a plain screenshot stays one keystroke
/// away.
struct FrameDressingPopover: View {
    @ObservedObject var editor: ScreenshotEditor
    var lang: AppLanguage

    var body: some View {
        MarkupPopoverBody {
            Toggle(isOn: Binding(
                get: { editor.dressing.isOn },
                set: { editor.dressing.isOn = $0; editor.refreshPreview() }
            )) {
                Text(L10n.t(.dressLabel, lang)).font(Theme.mono(12))
            }
            .toggleStyle(.switch)

            if editor.dressing.isOn {
                backgrounds
                MarkupStepper(title: L10n.t(.dressPadding, lang), value: $editor.dressing.padding,
                              range: 0...20) { editor.refreshPreview() }
                MarkupStepper(title: L10n.t(.dressCorners, lang), value: $editor.dressing.corners,
                              range: 0...20) { editor.refreshPreview() }
                MarkupStepper(title: L10n.t(.dressShadow, lang), value: $editor.dressing.shadow,
                              range: 0...20) { editor.refreshPreview() }

                Toggle(isOn: Binding(
                    get: { editor.dressing.browserFrame },
                    set: { editor.dressing.browserFrame = $0; editor.refreshPreview() }
                )) {
                    Text(L10n.t(.dressBrowser, lang)).font(Theme.mono(11))
                }
                .toggleStyle(.switch)

                if editor.dressing.browserFrame {
                    TextField(L10n.t(.dressAddress, lang), text: Binding(
                        get: { editor.dressing.address },
                        set: { editor.dressing.address = $0; editor.refreshPreview() }
                    ))
                    .textFieldStyle(.plain)
                    .font(Theme.mono(11))
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldBg))
                }

                Button(L10n.t(.resetDefaults, lang)) {
                    editor.dressing = .standard
                    editor.dressing.isOn = true
                    editor.refreshPreview()
                }
                .buttonStyle(.plain)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var backgrounds: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(.dressBackground, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 8) {
                ForEach(0..<FrameDressingRenderer.presets.count, id: \.self) { index in
                    let pair = FrameDressingRenderer.presets[index]
                    Button {
                        editor.dressing.background = .preset(index)
                        editor.refreshPreview()
                    } label: {
                        LinearGradient(colors: [Color(nsColor: pair.0), Color(nsColor: pair.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Theme.glyphInk.opacity(chosen(index) ? 0.9 : 0.16),
                                                  lineWidth: chosen(index) ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chosen(_ index: Int) -> Bool {
        if case .preset(let current) = editor.dressing.background { return current == index }
        return false
    }
}

/// The mark stamped over the picture: where it sits, how big, how faint, and
/// whether it repeats across the whole frame.
struct WatermarkPopover: View {
    @ObservedObject var editor: ScreenshotEditor
    var lang: AppLanguage

    var body: some View {
        MarkupPopoverBody {
            Toggle(isOn: Binding(
                get: { editor.watermark.isOn },
                set: { editor.watermark.isOn = $0; editor.refreshPreview() }
            )) {
                Text(L10n.t(.markLabel, lang)).font(Theme.mono(12))
            }
            .toggleStyle(.switch)

            if editor.watermark.isOn {
                TextField(L10n.t(.markText, lang), text: Binding(
                    get: { editor.watermark.text },
                    set: { editor.watermark.text = $0; editor.refreshPreview() }
                ))
                .textFieldStyle(.plain)
                .font(Theme.mono(11))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.fieldBg))

                Button(L10n.t(.markImage, lang)) { pickImage() }
                    .buttonStyle(.plain)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textSecondary)

                MarkupStepper(title: L10n.t(.markOpacity, lang), value: $editor.watermark.opacity,
                              range: 5...100) { editor.refreshPreview() }
                MarkupStepper(title: L10n.t(.markSize, lang), value: $editor.watermark.size,
                              range: 1...20) { editor.refreshPreview() }

                Toggle(isOn: Binding(
                    get: { editor.watermark.tiled },
                    set: { editor.watermark.tiled = $0; editor.refreshPreview() }
                )) {
                    Text(L10n.t(.markTiled, lang)).font(Theme.mono(11))
                }
                .toggleStyle(.switch)

                // A tile covers the whole frame; a corner is meaningless then.
                if !editor.watermark.tiled { spots }
            }
        }
    }

    private var spots: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t(.markSpot, lang)).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 6) {
                ForEach(Watermark.Spot.allCases, id: \.self) { spot in
                    Button {
                        editor.watermark.spot = spot
                        editor.refreshPreview()
                    } label: {
                        Text(spotMark(spot))
                            .font(Theme.mono(10))
                            .frame(width: 30, height: 26)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(editor.watermark.spot == spot ? Theme.chipBg : Theme.rowBg))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func spotMark(_ spot: Watermark.Spot) -> String {
        switch spot {
        case .topLeading: return "◤"
        case .topTrailing: return "◥"
        case .bottomLeading: return "◣"
        case .bottomTrailing: return "◢"
        case .centre: return "◈"
        }
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        editor.watermark.imageName = WatermarkRenderer.store(imageAt: url)
        editor.refreshPreview()
    }
}

/// The shell both popovers share: one width, one padding, and a ceiling on the
/// height so a long panel scrolls instead of running off the screen.
private struct MarkupPopoverBody<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(14)
            .frame(width: 246, alignment: .leading)
        }
        .frame(width: 246)
        .frame(maxHeight: 430)
        .background(Theme.background)
    }
}

/// A slider that names what it changes and shows the number it is on.
private struct MarkupStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var settled: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(value)").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                onEditingChanged: { editing in if !editing { settled() } }
            )
        }
    }
}
